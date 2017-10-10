

module BRAM6k9bit(CLK, ADDR, WE, EN, DIN, DINP, DOUT, DOUTP);
input CLK;
input WE;
input EN;
input [12:0] ADDR;
input [7:0] DIN;
input DINP;
output [7:0] DOUT;
output DOUTP;

wire [7:0] ram0_DOUT, ram1_DOUT, ram2_DOUT;
wire ram0_DOUTP, ram1_DOUTP, ram2_DOUTP;

reg [3:0] ram_EN;
always @*
begin
  #1;
  ram_EN = 0;
  ram_EN[ADDR[12:11]] = EN;
end


//
// Output mux...
//
reg [1:0] dly_ADDR, next_dly_ADDR;
always @(posedge CLK)
begin
  dly_ADDR = next_dly_ADDR;
end

always @*
begin
  #1;
  next_dly_ADDR = ADDR[12:11];
end

reg [7:0] DOUT;
reg DOUTP;
always @*
begin
  #1;
  DOUT = 8'h0;
  DOUTP = 1'b0;
  case (dly_ADDR)
    2'h0 : begin DOUT = ram0_DOUT; DOUTP = ram0_DOUTP; end
    2'h1 : begin DOUT = ram1_DOUT; DOUTP = ram1_DOUTP; end
    2'h2 : begin DOUT = ram2_DOUT; DOUTP = ram2_DOUTP; end
  endcase
end


//
// Instantiate the 2Kx8 RAM's...
//
RAMB16_S9 ram0 (
  .CLK(CLK), .ADDR(ADDR[10:0]),
  .DI(DIN), .DIP(DINP), 
  .DO(ram0_DOUT), .DOP(ram0_DOUTP),
  .EN(ram_EN[0]), .SSR(1'b0), .WE(WE)); 


RAMB16_S9 ram1 (
  .CLK(CLK), .ADDR(ADDR[10:0]),
  .DI(DIN), .DIP(DINP), 
  .DO(ram1_DOUT), .DOP(ram1_DOUTP),
  .EN(ram_EN[1]),
  .SSR(1'b0),
  .WE(WE));


RAMB16_S9 ram2 (
  .CLK(CLK), .ADDR(ADDR[10:0]),
  .DI(DIN), .DIP(DINP), 
  .DO(ram2_DOUT), .DOP(ram2_DOUTP),
  .EN(ram_EN[2]),
  .SSR(1'b0),
  .WE(WE));

endmodule

