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
// Instantaite RLE...
//
reg enable, arm;
reg [1:0] rle_mode;
reg [3:0] disabledGroups;
reg [31:0] dataIn;
reg validIn;
wire [31:0] dataOut;
rle_enc rle (clock, reset, enable, arm, rle_mode, disabledGroups, dataIn, validIn, dataOut, validOut);


reg [31:0] last_dataOut;
initial last_dataOut = 0;
always @ (posedge clock)
begin
  #1;
  if (enable && validOut)
    begin
      case (disabledGroups)
        4'b1110 : if (dataOut[7])  
		    $display ("%t: RLE=%d. Value=%x", $realtime, dataOut[6:0], last_dataOut[6:0]); 
	          else 
		    begin
		      $display ("%t: Value=%x", $realtime, dataOut[6:0]); 
		      last_dataOut = dataOut;
		    end

        4'b1100 : if (dataOut[15])
		    $display ("%t: RLE=%d. Value=%x", $realtime, dataOut[14:0], last_dataOut[14:0]); 
	          else 
		    begin
		      $display ("%t: Value=%x", $realtime, dataOut[14:0]); 
		      last_dataOut = dataOut;
		    end

        default : if (dataOut[31]) 
		    $display ("%t: RLE=%d. Value=%x", $realtime, dataOut[30:0], last_dataOut[30:0]); 
	          else 
		    begin
		      $display ("%t: Value=%x", $realtime, dataOut[30:0]); 
		      last_dataOut = dataOut;
		    end
      endcase
    end
end


//
// Generate sequence of data...
//
task issue_block;
input [31:0] count;
input [31:0] value;
integer i;
begin
//  $display ("%t: count=%d  value=%08x",$realtime,count,value);
  #1; dataIn = ~value; validIn = 1'b1; @(posedge clock);
  for (i=0; i<count; i=i+1) begin #1; dataIn = value; validIn = 1'b1; @(posedge clock); end
end
endtask

task issue_pattern;
begin
  #1; dataIn = 32'h41414141; validIn = 1'b1; @(posedge clock);
  #1; dataIn = 32'h42424242; validIn = 1'b0; @(posedge clock);
  #1; dataIn = 32'h43434343; validIn = 1'b1; @(posedge clock);
  #1; dataIn = 32'h43434343; validIn = 1'b0; @(posedge clock);
  #1; dataIn = 32'h43434343; validIn = 1'b0; @(posedge clock);
  #1; dataIn = 32'h43434343; validIn = 1'b1; @(posedge clock);

  issue_block(2,32'h44444444);
  issue_block(3,32'h45454545);
  issue_block(4,32'h46464646);
  issue_block(8,32'h47474747);
  issue_block(16,32'h48484848);
  issue_block(32,32'h49494949);
  issue_block(64,32'h4A4A4A4A);
  issue_block(128,32'h4B4B4B4B);
  issue_block(129,32'h4C4C4C4C);
  issue_block(130,32'h4D4D4D4D);
  issue_block(131,32'h4E4E4E4E);
  issue_block(256,32'h4F4F4F4F);
  issue_block(512,32'h50505050);
  issue_block(1024,32'h51515151);
  issue_block(2048,32'h52525252);
  issue_block(4096,32'h53535353);
  issue_block(8192,32'h54545454);
  issue_block(16384,32'h55555555);
  issue_block(32768,32'h56565656);
  issue_block(65536,32'h57575757);

  repeat (10) begin #1; dataIn = 32'hFFFFFFFF; validIn = 1'b0; @(posedge clock); end
end
endtask


//
// Generate test sequence...
//
initial
begin
  enable = 0;
  arm = 1;
  repeat (10) @(posedge clock);
  reset = 0;
  rle_mode = 0;
  disabledGroups = 4'b1110; // 8'bit mode

  repeat (10) @(posedge clock);
  issue_pattern();

  repeat (10) @(posedge clock);
  enable = 1; // turn on RLE...

  repeat (10) @(posedge clock);
  fork
    begin
      issue_pattern();
    end
    begin
      repeat (48000) @(posedge clock);
      #1 enable = 0;     
    end
  join

  repeat (10) @(posedge clock);
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


