`timescale 1ns/100ps

module testbench();

reg clock, reset;
initial begin clock=0; reset=1; end
always
begin
  #10;
  clock = !clock;
end



//
// Instantiate advanced trigger...
//
reg validIn;
reg [31:0] dataIn;
reg arm;
reg wrSelect, wrChain;
reg [31:0] config_data;

trigger_adv adv (
  clock, reset, 
  dataIn, validIn, arm,
  wrSelect, wrChain, config_data,
  // outputs...
  run, capture);


always @ (posedge clock)
begin
  #1;
  if (capture) $display ("%t: Capture", $realtime);
  if (run) $display ("%t: Run (triggered)", $realtime);
end


task issue_idle;
begin
  #1; dataIn = 0; validIn=1'b1;
  @(posedge clock);
  #0.1; validIn=1'b0;
end
endtask


task issue_data;
input [31:0] value;
begin
  $display ("%t: Issue Data: %08x", $realtime, value);
  #1; dataIn = value; validIn=1'b1;
  @(posedge clock);
  #0.1; validIn=1'b0;
end
endtask


task write_select;
input [31:0] value;
begin
  #1; config_data = value; wrSelect = 1'b1; 
  @(posedge clock);
  #0.1; wrSelect = 1'b0;
end
endtask


task write_chain;
input [31:0] value;
begin
  #1; config_data = value; wrChain = 1'b1; 
  @(posedge clock);
  #1; wrChain = 1'b0;
  repeat (32) @(posedge clock);
end
endtask


// Write trigger state...
task write_trigstate;
input [3:0] state;
input trigger;
input [1:0] start_timer;
input [1:0] clear_timer;
input [1:0] stop_timer;
input [3:0] else_state;
input [19:0] obtain_count;
begin
  write_select(state);
  write_chain({trigger,start_timer,clear_timer,stop_timer,else_state,obtain_count});
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
  OP_NOP=0, OP_AND=1, OP_NAND=2, OP_OR=3, OP_NOR=4, OP_XOR=5, OP_NXOR=6, OP_A=7, OP_B=8;

reg [15:0] pairvalue[0:8];
reg [15:0] midvalue[0:8];
reg [15:0] finalvalue[0:8];
initial
begin
  pairvalue[0]=16'h0000; midvalue[0]=16'h0000; finalvalue[0]=16'h0000; // NOP
  pairvalue[1]=16'h8000; midvalue[1]=16'h8000; finalvalue[1]=16'h0008; // AND
  pairvalue[2]=16'h7FFF; midvalue[2]=16'h7FFF; finalvalue[2]=16'h0007; // NAND
  pairvalue[3]=16'hF888; midvalue[3]=16'hFFFE; finalvalue[3]=16'h000E; // OR
  pairvalue[4]=16'h0777; midvalue[4]=16'h0001; finalvalue[4]=16'h0001; // NOR
  pairvalue[5]=16'h7888; midvalue[5]=16'h0116; finalvalue[5]=16'h0006; // XOR
  pairvalue[6]=16'h8777; midvalue[6]=16'hFEE9; finalvalue[6]=16'h0009; // NXOR
  pairvalue[7]=16'h8888; // A-only
  pairvalue[8]=16'hF000; // B-only
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
begin : test
  integer i;

  validIn=0;
  dataIn=0;
  arm=0;
  wrSelect=0;
  wrChain=0;
  config_data=0;

  repeat (10) @(posedge clock);
  reset = 0;
  repeat (10) @(posedge clock);

  // Configure simple two state trigger...

  $display ("%t: Trigger Terms...", $realtime);
  //               term,  value,         mask
  write_trigterm  (  0,   32'h00000011,  32'h000000FF); // terma = look for 0x11 in bits[7:0]
  write_trigterm  (  1,   32'h00000042,  32'h000000FF); // termb = look for 0x42 in bits[7:0]
  write_trigterm  (  2,   32'h00000033,  32'h000000FF); // termc = look for 0x33 in bits[7:0]
  for (i=3; i<10; i=i+1) write_trigterm  (i, 32'h00000000, 32'h00000000); 


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


  $display ("%t: Trigger State FSM...", $realtime);
  //               state, trig, starttimer, cleartimer, stoptimer, elsestate, obtaincount
  write_trigstate (4'h0,   1'b0,  2'b00,       2'b0,       2'b0,      4'h0,     20'h0); // on hit goto 1
  write_trigstate (4'h1,   1'b0,  2'b01,       2'b0,       2'b0,      4'h0,     20'h0); // on hit start timer1 & goto 2, else 0
  write_trigstate (4'h2,   1'b0,  2'b00,       2'b0,       2'b0,      4'h1,     20'h0); // on hit goto 3, else 1
  write_trigstate (4'h3,   1'b1,  2'b00,       2'b0,       2'b0,      4'h2,     20'h0); // on hit trigger, else 2


  // Trigsum fields:
  //   term: 0=hit, 1=else, 2=capture
  //   ops:  OP_AND, OP_NAND, OP_OR, OP_NOR, OP_XOR, OP_NXOR, OP_A, OP_B, OP_NOP

  $display ("%t: Trigger State Combination/Summing Ops...", $realtime);
  //            state, term, ab,     c-r1,   d-e1,   e-t1,   fg,     h-r2,   i-e2,   j-t2,   mid1,  mid2,  final
  write_trigsum ( 0,    0,   OP_A,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // hit=terma (0x11)
  write_trigsum ( 0,    1,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // nop
  write_trigsum ( 0,    2,   OP_A,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // capture=terma

  write_trigsum ( 1,    0,   OP_B,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // hit=termb (0x42)
  write_trigsum ( 1,    1,   OP_A,   OP_A,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // else=terma | termc (0x11 or 0x33)
  write_trigsum ( 1,    2,   OP_B,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // capture=termb 

  write_trigsum ( 2,    0,   OP_NOP, OP_NOP, OP_NOP, OP_B,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // hit=timer1 
  write_trigsum ( 2,    1,   OP_NOP, OP_NOP, OP_B,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // else-edge1
  write_trigsum ( 2,    2,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR);

  write_trigsum ( 3,    0,   OP_NOP, OP_B,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR); // hit=range1
  write_trigsum ( 3,    1,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR);
  write_trigsum ( 3,    2,   OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_NOP, OP_OR, OP_OR, OP_OR);

  repeat (10) @(posedge clock);
  #1; arm=1;
  repeat (10) @(posedge clock);

  issue_data (32'h0); // start in state 0
  issue_data (32'h0); // nop

  issue_data (32'h0); // nop
  issue_data (32'h0); // nop

  issue_data (32'h00000001); // nop
  issue_data (32'h00000011); // goes to state 1

  issue_data (32'h0); // nop
  issue_data (32'h0); // nop
  issue_data (32'h0); // nop
  issue_data (32'h0); // nop
  issue_data (32'h0); // nop
  issue_data (32'h0); // nop
  issue_data (32'h0); // nop
  issue_data (32'h0); // nop

  issue_data (32'h00000011); // go back to state 0
  issue_data (32'h00000001); // nop

  issue_data (32'h00000011); // go back to state 1
  issue_data (32'h00000001); // nop

  issue_data (32'h00000033); // go back to state 0
  issue_data (32'h00000003); // nop

  issue_data (32'h00000011); // go back to state 1
  issue_data (32'h00000001); // nop

  issue_data (32'h00000002); // nop
  issue_data (32'h00000042); // goto state 2

  // waiting for state 3...
  repeat (500) issue_idle; // wait for state 3
  issue_data (32'h80002345); // hits range, but nop because still in state 2
  issue_data (32'h80000000); // 
  issue_data (32'h00000000); // falling edge - back to state 1
  issue_data (32'h00000042); // back to state 2
  issue_data (32'h00010000); // rising edge - back to state 1
  issue_data (32'h00000042); // back to state 2

  repeat (1000) issue_idle; // wait for state 3
  issue_data (32'h00002345); // trigger!

  repeat (100) issue_idle;
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
endmodule


