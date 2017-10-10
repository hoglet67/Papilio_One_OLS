`timescale 1ns/100ps


//
// Full Logic Sniffer version of advanced trigger testbench... much slower...
//
module testbench();

reg bf_clock;
initial bf_clock=0;
always
begin
  #10;
  bf_clock = !bf_clock;
end

reg sclk, mosi, cs;
initial begin sclk=0; mosi=1'b0; cs=1'b1; end

wire [31:0] indata; // Since indata can drive data, must create a "bus" assignment.
reg [31:0] indata_reg;
reg indata_oe;
initial
begin 
  indata_reg = 32'h0;
  indata_oe = 1'b0; 
  #10;
  indata_oe = 1'b1; // turn on output enable
end
assign indata = (indata_oe) ? indata_reg : 32'hzzzzzzzz;


//
// Instantiate the Logic Sniffer...
//
wire extClockIn = 1'b0;
wire extTriggerIn = 1'b0;

Logic_Sniffer sniffer (
  .bf_clock(bf_clock),
  .extClockIn(extClockIn),
  .extClockOut(extClockOut),
  .extTriggerIn(extTriggerIn),
  .extTriggerOut(extTriggerOut),
  .indata(indata),
  .miso(miso), 
  .mosi(mosi), 
  .sclk(sclk), 
  .cs(cs),
  .dataReady(dataReady),
  .armLEDnn(armLEDnn),
  .triggerLEDnn(triggerLEDnn));


//
// PIC emulator...
//
reg wrbyte_req;
reg [7:0] wrbyte_data;
initial begin wrbyte_req=0; wrbyte_data=0; end
always @(posedge wrbyte_req)
begin : temp
  integer i;
  i = 7;
  cs = 0;
  #100;
  repeat (8) 
    begin 
      sclk = 0; mosi = wrbyte_data[i]; i=i-1; #50;
      sclk = 1; #50;
    end
  sclk = 0;
  mosi = 0;
  #100;
  cs = 1;
  #100;
  wrbyte_req = 0;
end


//
// Generate SPI test commands...
//
task write_cmd;
input [7:0] value;
integer i;
begin 
  wrbyte_req = 1;
  wrbyte_data = value;
  @(negedge wrbyte_req);
end
endtask

task write_longcmd;
input [7:0] opcode;
input [31:0] value;
begin
  write_cmd (opcode);
  write_cmd (value[7:0]);
  write_cmd (value[15:8]);
  write_cmd (value[23:16]);
  write_cmd (value[31:24]);
end
endtask


// Simulate behavior of PIC responding the dataReady asserting...
task wait4fpga;
begin
  while (!dataReady) @(posedge dataReady);
  while (dataReady) write_cmd(8'h7F);
end
endtask



//
// Monitor trigger...
//
initial
begin
  #100;
  @(posedge sniffer.core.capture);
  $display ("%t: Capture", $realtime);
end

initial
begin
  #100;
  @(posedge sniffer.core.run);
  $display ("%t: Run (triggered)", $realtime);
end



// Configure commands for trigger...
task write_select;
input [31:0] value;
begin
  write_longcmd (8'h9E, value);
end
endtask


task write_chain;
input [31:0] value;
begin
  write_longcmd (8'h9F, value);
end
endtask


// Write trigger state...
task write_trigstate;
input [3:0] state;
input laststate;
input trigger;
input [1:0] start_timer;
input [1:0] clear_timer;
input [1:0] stop_timer;
input [3:0] else_state;
input [19:0] obtain_count;
begin
  write_select(state);
  write_chain({laststate,trigger,start_timer,clear_timer,stop_timer,else_state,obtain_count});
end
endtask


// Write one of the 10 trigger terms...
task write_trigterm;
input [3:0] termnum;
input [31:0] value;
input [31:0] mask;
reg [4:0] i;
reg [15:0] x0,x1,x2,x3,y0,y1,y2,y3;
reg [31:0] compare;
reg [127:0] chain;
begin
  {x0,x1,x2,x3,y0,y1,y2,y3}=0;

  for (i=0; i<16; i=i+1)
    begin
      compare = ({~i[3:0],~i[3:0],~i[3:0],~i[3:0],~i[3:0],~i[3:0],~i[3:0],~i[3:0]} ^ value) & mask;
      x0 = {x0,~|compare[3:0]};
      x1 = {x1,~|compare[7:4]};
      x2 = {x2,~|compare[11:8]};
      x3 = {x3,~|compare[15:12]};
      y0 = {y0,~|compare[19:16]};
      y1 = {y1,~|compare[23:20]};
      y2 = {y2,~|compare[27:24]};
      y3 = {y3,~|compare[31:28]};
    end

  chain = {y3,y2,y1,y0,x3,x2,x1,x0};
  $display ("term %d: value=%x, mask=%x, chain=%x",termnum,value,mask,chain);

  // Write adv trigger select index...
  write_select(8'h20 + termnum);

  // Write adv trigger chain data...  Bit 127 is first shifted into the chain.
  write_chain(chain[127:96]);
  write_chain(chain[95:64]);
  write_chain(chain[63:32]);
  write_chain(chain[31:0]);
end
endtask


//
// Specify desired operations for combining trigger terms.
//   a-b, c-range1, d-edge1, e-timer1, f-g, h-range2, i-edge2, j-timer2 terms:
//
// Inputs:
//   statenum = which of the available states
//   stateterm = 0=hit-term, 1=else-term, 2=capture-term
//   op's = OP_AND, OP_NAND, OP_OR, OP_NOR4, OP_XOR, OP_NXOR, OP_A, OP_B, OP_NOP
//
// The op fields combine trigger-terms using one of the listed operations...
//
//   a      \__(op_ab)________
//   b      /                 \
//   c      \__(op_c_range1)___\
//   range1 /                   \__(op_mid1)__
//   d      \__(op_d_edge1)_____/             \
//   edge1  /                  /               \
//   e      \__(op_e_timer1)__/                 \
//   timer1 /                                    \__(op_final)__ hit
//   f      \__(op_fg)________                   /
//   g      /                 \                 /
//   h      \__(op_h_range2)___\               /
//   range2 /                   \__(op_mid2)__/
//   i      \__(op_i_edge2)_____/
//   edge2  /                  /
//   j      \__(op_j_timer2)__/
//   timer2 /
//
// The mid1/mid2 ops combine the first & last four edge op's respectfully.
// The final op combines the mid ops.
//
parameter [3:0] 
  OP_NOP=0, OP_ANY=1, OP_AND=2, OP_NAND=3, OP_OR=4, OP_NOR=5, OP_XOR=6, OP_NXOR=7, OP_A=8, OP_B=9;

reg [15:0] pairvalue[0:9];
reg [15:0] midvalue[0:9];
reg [15:0] finalvalue[0:9];
initial
begin
  pairvalue[0]=16'h0000; midvalue[0]=16'h0000; finalvalue[0]=16'h0000; // NOP
  pairvalue[1]=16'hFFFF; midvalue[1]=16'hFFFF; finalvalue[1]=16'hFFFF; // ANY
  pairvalue[2]=16'h8000; midvalue[2]=16'h8000; finalvalue[2]=16'h0008; // AND
  pairvalue[3]=16'h7FFF; midvalue[3]=16'h7FFF; finalvalue[3]=16'h0007; // NAND
  pairvalue[4]=16'hF888; midvalue[4]=16'hFFFE; finalvalue[4]=16'h000E; // OR
  pairvalue[5]=16'h0777; midvalue[5]=16'h0001; finalvalue[5]=16'h0001; // NOR
  pairvalue[6]=16'h7888; midvalue[6]=16'h0116; finalvalue[6]=16'h0006; // XOR
  pairvalue[7]=16'h8777; midvalue[7]=16'hFEE9; finalvalue[7]=16'h0009; // NXOR
  pairvalue[8]=16'h8888; midvalue[8]=16'hEEEE; finalvalue[8]=16'h0002; // A-only
  pairvalue[9]=16'hF000; midvalue[9]=16'hFFF0; finalvalue[9]=16'h0004; // B-only
end

task write_trigsum;
input [3:0] statenum;
input [1:0] stateterm; 
input [3:0] op_ab, op_c_range1, op_d_edge1, op_e_timer1; // edge sums
input [3:0] op_fg, op_h_range2, op_i_edge2, op_j_timer2;
input [3:0] op_mid1, op_mid2, op_final; 
reg [191:0] chain;
begin
  write_select (8'h40+(statenum*4)+stateterm);

  chain = {
    16'h0, // padding to make 32-bit aligned
    finalvalue[op_final],
    midvalue[op_mid2],
    midvalue[op_mid1],
    pairvalue[op_j_timer2],
    pairvalue[op_i_edge2],
    pairvalue[op_h_range2],
    pairvalue[op_fg],
    pairvalue[op_e_timer1],
    pairvalue[op_d_edge1],
    pairvalue[op_c_range1],
    pairvalue[op_ab]};

  $display ("termsum state/term %d/%d: %d/%d/%d/%d/%d/%d/%d/%d %d/%d/%d, chain=%x",
    statenum, stateterm,
    op_ab, op_c_range1, op_d_edge1, op_e_timer1,
    op_fg, op_h_range2, op_i_edge2, op_j_timer2,
    op_mid1, op_mid2, op_final,
    chain);

  // Write adv trigger chain data...  MSB is first shifted into the chain.
  write_chain(chain[191:160]);
  write_chain(chain[159:128]);
  write_chain(chain[127:96]);
  write_chain(chain[95:64]);
  write_chain(chain[63:32]);
  write_chain(chain[31:0]);
end
endtask


//
// The range detectors are basically just carry-look-ahead adders.
// They are setup to "add" a value to in the input.  If the carry output
// asserts, then they hit.
//
// 32-bit adders are used (two for each range check).  If the sum
// of the input & the programed value are greater than 0xFFFFFFFF
// then the adder "carry" output asserts, indicating a hit.
//
// Lower value carry's are used directly.  Upper value carry's are 
// inverted to produce the following tests:
//    indata >= lower
//    indata <= upper 
//
// Individual CLB LUT RAM's are configured to XOR between input
// on LUT addr 0 & the target value.
//
// ------------------------------------------------------------------
//
// It is possible for this to range check a non-contiguous value.
// ie: range check on indata bits 0, 7, 9, 11, 15 & no others.
//
// To do this, the disused range bit CLB's must be configured to NOP
// and not disturb the fast-carry-chain connecting them.
//
// LUT RAM's of disused CLB should be set to all 1's (ie: 0xFFFF).
//
// ------------------------------------------------------------------
//
// A given range target is bitwise inverted before being programmed
// (see code below).  For non-contigues range checks, it must also be 
// spaced out (currently not supported by this task).
//
//   Lower values:  ~(target-1)
//   Upper values:  ~target
//
// Yields a hit if: (upper >= indata >= lower)
//
// ------------------------------------------------------------------
//
// Example:
//    lower=0x10000000.     value-to-program-for-lower=0xF0000000 = ~(0x10000000-1)
//    upper=0xE0000000.     value-to-program-for-upper=0x1FFFFFFF = ~(0xE0000000)
//
//    If indata=0x00000100, then lower misses.  No match.  Miss.
//    If indata=0x0FFFFFFF, then lower misses (0x0FFFFFFF+0xF0000000 = no carry).  Miss.
//    If indata=0x10000000, then lower hits (0x1000000+0xF000000 = lower-carry) & upper hits.  Match!
//    If indata=0xE0000000, then lower hits & upper hits.  Match!
//    If indata=0xE0000001, then lower hits & upper misses (0xE0000001+0x1FFFFFFF = upper-carry).  Miss!
//
parameter RANGE_XOR0 = 16'hAAAA;
parameter RANGE_XOR1 = 16'h5555;

task write_range;
input [1:0] rangesel; // 0=range1-lower, 1=range1-upper, 2=range2-lower, 3=range2-upper
input [31:0] target;
reg [31:0] value;
reg [31:0] chain; // Full chain is 16X this (512 bits total)
integer i;
begin
  write_select (8'h30+rangesel);

  if (rangesel[0])
    value = ~target; // upper target
  else value = ~(target-1); // lower value

  // Write adv trigger chain data...  MSB is first shifted into the chain.
  for (i=0; i<16; i=i+1)
    begin
      chain = (value[31]) ? RANGE_XOR1 : RANGE_XOR0;
      chain = {chain, (value[30]) ? RANGE_XOR1 : RANGE_XOR0};
      $display ("range %d:  i=%d  chain=%x",rangesel, i, chain);
      value = {value,2'b0};
      write_chain(chain);
    end
end
endtask



//
// The edge detector uses delay flops to detect rising & falling edges, both, or neither.
// Each 4-input CLB evalutes two bits of input, and two bits of delayed input.
//
parameter 
  EDGE_RISE0=16'h0A0A, 
  EDGE_RISE1=16'h00CC, 
  EDGE_FALL0=16'h5050, 
  EDGE_FALL1=16'h3300,
  EDGE_BOTH0=16'h5A5A, // rise0|fall0
  EDGE_BOTH1=16'h33CC, // rise1|fall1
  EDGE_NEITHER0=16'hA5A5, // ~both0
  EDGE_NEITHER1=16'hCC33; // ~both1

task write_edge;
input edgesel; // 0=edge1, 1=edge2
input [31:0] rising_edges;
input [31:0] falling_edges;
input [31:0] neither_edge;
reg [255:0] chain;
begin
  write_select (8'h34+edgesel);

  chain = 0;
  for (i=31; i>0; i=i-2)
    begin
      chain = {chain,16'h0};
      if (neither_edge[i])
        chain[15:0] = chain[15:0] | EDGE_NEITHER1; // neither edge
      else
        case ({rising_edges[i],falling_edges[i]})
          2'b01 : chain[15:0] = chain[15:0] | EDGE_FALL1; // falling edges
          2'b10 : chain[15:0] = chain[15:0] | EDGE_RISE1; // rising edges
          2'b11 : chain[15:0] = chain[15:0] | EDGE_BOTH1; // both edges
        endcase

      if (neither_edge[i-1])
        chain[15:0] = chain[15:0] | EDGE_NEITHER0; // neither edge
      else
        case ({rising_edges[i-1],falling_edges[i-1]})
          2'b01 : chain[15:0] = chain[15:0] | EDGE_FALL0; // falling edges
          2'b10 : chain[15:0] = chain[15:0] | EDGE_RISE0; // rising edges
          2'b11 : chain[15:0] = chain[15:0] | EDGE_BOTH0; // both edges
        endcase
    end

  // Write adv trigger chain data...  MSB is first shifted into the chain.
  write_chain(chain[255:224]);
  write_chain(chain[223:192]);
  write_chain(chain[191:160]);
  write_chain(chain[159:128]);
  write_chain(chain[127:96]); 
  write_chain(chain[95:64]); 
  write_chain(chain[63:32]);
  write_chain(chain[31:0]);
end
endtask


task write_timer_limit;
input timersel;
input [35:0] value;
begin
  write_select (8'h38+timersel*2);
  write_chain (value[31:0]);
  write_select (8'h39+timersel*2);
  write_chain ({28'h0,value[35:32]});
end
endtask



//
// Generate test sequence...
//
initial
begin
  indata_reg = 0;
  #100;

  $display ("%t: Reset...", $realtime);
  write_cmd (8'h00); write_cmd (8'h00); write_cmd (8'h00); write_cmd (8'h00); write_cmd (8'h00);

  $display ("%t: Query ID...", $realtime);
  write_cmd (8'h02); wait4fpga();

  $display ("%t: Flags...  8-bit capture, internal test pattern", $realtime);
  write_longcmd (8'h82, 32'h00000800 | {4'hE, 2'h0});

  $display ("%t: Divider... (max sample rate)", $realtime);
  write_longcmd (8'h80, 32'h00000000);

  $display ("%t: Read & Delay Count...", $realtime);
  write_longcmd (8'h81, 32'h00040004);

  //
  // Configure very simple trigger...
  //
  $display ("%t: Zero all Trigger Terms...", $realtime);
  write_trigterm  ( 15,   32'h00000000,  32'h00000000); // zero all trig terms

  $display ("%t: Trigger Term 0...", $realtime);
  write_trigterm  (  0,   32'h00000001,  32'h00000001); // terma = look for 0x01 in bits[7:0]

/*
  $display ("%t: Trigger Range 1 Lower...", $realtime);
  write_range (0, 32'h00001234); 
  $display ("%t: Trigger Range 1 Upper...", $realtime);
  write_range (1, 32'h00005678);
  $display ("%t: Trigger Range 2 Lower...", $realtime);
  write_range (2, 32'h00009ABC);
  $display ("%t: Trigger Range 2 Upper...", $realtime);
  write_range (3, 32'h0000DEF0);

  $display ("%t: Trigger Edges...", $realtime);
  write_edge (0, 32'h04010000, 32'h80200000, 32'h00000000); // edge1
  write_edge (1, 32'h00000000, 32'h00000000, 32'h00000000); // edge2

  $display ("%t: Trigger Timer Limits...", $realtime);
  write_timer_limit (0, 1000);   // 10000ns   (1000 clocks)
  write_timer_limit (1, 100000); // 1000000ns (100000 clocks)
*/

  $display ("%t: Trigger State FSM...", $realtime);
  //               state, last, trig, starttimer, cleartimer, stoptimer, elsestate, obtaincount
  for (i=0; i<1; i=i+1)
    write_trigstate (i,   1'b1, 1'b1,  2'b00,       2'b0,       2'b0,      4'h0,     20'h0); // on hit trigger


  // Trigsum fields:
  //   term: 0=hit, 1=else, 2=capture
  //   ops:  OP_AND, OP_NAND, OP_OR, OP_NOR, OP_XOR, OP_NXOR, OP_A, OP_B, OP_NOP

  $display ("%t: Trigger State Combination/Summing Ops...", $realtime);
  //            state, term, ab,     c-r1,   d-e1,   e-t1,   fg,     h-r2,   i-e2,   j-t2,   mid1,  mid2,  final
  write_trigsum ( 0,    0,   OP_A,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // hit=terma (0x11)
  write_trigsum ( 0,    1,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // nop
  write_trigsum ( 0,    2,   OP_A,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // capture=terma

/*
  write_trigsum ( 1,    0,   OP_B,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // hit=termb (0x42)
  write_trigsum ( 1,    1,   OP_A,   OP_A,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // else=terma | termc (0x11 or 0x33)
  write_trigsum ( 1,    2,   OP_B,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // capture=termb 

  write_trigsum ( 2,    0,   OP_NOP, OP_NOP, OP_NOP, OP_B,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // hit=timer1 
  write_trigsum ( 2,    1,   OP_NOP, OP_NOP, OP_B,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // else-edge1
  write_trigsum ( 2,    2,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR);

  write_trigsum ( 3,    0,   OP_NOP, OP_B,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // hit=range1
  write_trigsum ( 3,    1,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR);
  write_trigsum ( 3,    2,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR);
*/

  $display ("%t: Arm Advanced Trigger...", $realtime);
  write_cmd (8'h0F);
  wait4fpga();

  repeat (5) @(posedge bf_clock);

  write_cmd (8'h00); // verify finished flag gets cleared
  repeat (20) @(posedge bf_clock);

  $finish;
end



//
// Initialized wavedump...
//
reg [0:511] targetsst[0:0];
reg gotsst;
integer i;

initial 
begin
  $timeformat (-9,1," ns",0);
  $display ("%t: Starting wave dump...",$realtime);
  $dumpfile ("waves.dump");
  $dumpvars(0);
end


reg [7:0] miso_byte = 0;
integer miso_count = 0;
always @(posedge sclk)
begin
  #50;
  if (cs) 
    begin
      miso_byte=8'hzz; 
      miso_count=0;
    end
  else 
    begin
      miso_byte = {miso_byte[6:0],miso};
      miso_count=miso_count+1;
    end

  if (miso_count<8)
    $display ("%t: wr=%d   rd=%d",$realtime, mosi, miso);
  else if ((miso_byte>=32) && (miso_byte<128))
    begin
      $display ("%t: wr=%d   rd=%d (0x%02x) '%c'",$realtime, mosi, miso, miso_byte, miso_byte);
      miso_count=0;
    end
  else
    begin
      $display ("%t: wr=%d   rd=%d (0x%02x)",$realtime, mosi, miso, miso_byte);
      miso_count=0;
    end
end

always #10000
begin
  $display ("%t",$realtime);
end
endmodule


