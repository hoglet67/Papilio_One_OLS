//--------------------------------------------------------------------------------
// clockman.vhd
//
// Author: Michael "Mr. Sump" Poppitz
//
// Details: http://www.sump.org/projects/analyzer/
//
// This is only a wrapper for Xilinx' DCM component so it doesn't
// have to go in the main code and can be replaced more easily.
//
// Creates 100Mhz core clk0 from 32Mhz input reference clock.
//
//--------------------------------------------------------------------------------
//
// 12/29/2010 - Verilog Version created by Ian Davis - mygizmos.org
// 

`timescale 1ns/100ps

module pll_wrapper (clkin, clk0);
input clkin; // clock input
output clk0; // double clock rate output

parameter TRUE = 1'b1;
parameter FALSE = 1'b0;

wire clkin;
wire clk0;

wire clkfb; 
wire clkfbbuf; 

DCM_SP #(
  .CLKDV_DIVIDE(2.0), // Divide by: 1.5,2.0,2.5,3.0,3.5,4.0,4.5,5.0,5.5,6.0,6.5
  // 7.0,7.5,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0 or 16.0
  .CLKFX_DIVIDE(8),   // Can be any integer from 1 to 32
  .CLKFX_MULTIPLY(25), // Can be any integer from 2 to 32
  .CLKIN_DIVIDE_BY_2("FALSE"), // TRUE/FALSE to enable CLKIN divide by two feature
  .CLKIN_PERIOD(31.250), // Specify period of input clock
  .CLKOUT_PHASE_SHIFT("NONE"), // Specify phase shift of NONE, FIXED or VARIABLE
  .CLK_FEEDBACK("1X"), // Specify clock feedback of NONE, 1X or 2X
  .DESKEW_ADJUST("SYSTEM_SYNCHRONOUS"), // SOURCE_SYNCHRONOUS, SYSTEM_SYNCHRONOUS or
  // an integer from 0 to 15
  .DLL_FREQUENCY_MODE("LOW"), // HIGH or LOW frequency mode for DLL
  .DFS_FREQUENCY_MODE("LOW"), // HIGH or LOW frequency mode for DFS
  .DUTY_CYCLE_CORRECTION("TRUE"), // Duty cycle correction, TRUE or FALSE
  .PHASE_SHIFT(0),    // Amount of fixed phase shift from -255 to 255
  .STARTUP_WAIT("FALSE") // Delay configuration DONE until DCM LOCK, TRUE/FALSE
  ) DCM_baseClock (
  .CLK0(clkfb),     // 0 degree DCM CLK output
  .CLK180(), // 180 degree DCM CLK output
  .CLK270(), // 270 degree DCM CLK output
  .CLK2X(),   // 2X DCM CLK output
  .CLK2X180(), // 2X, 180 degree DCM CLK out
  .CLK90(),   // 90 degree DCM CLK output
  .CLKDV(),   // Divided DCM CLK out (CLKDV_DIVIDE)
  .CLKFX(CLKFX),   // DCM CLK synthesis out (M/D)
  .CLKFX180(CLKFX180), // 180 degree CLK synthesis out
  .LOCKED(LOCKED), // DCM LOCK status output
  .PSDONE(PSDONE), // Dynamic phase adjust done output
  .STATUS(STATUS), // 8-bit DCM status bits output
  .CLKFB(clkfbbuf),   // DCM clock feedback
  .CLKIN(clkin),   // Clock input (from IBUFG, BUFG or DCM)
  .PSCLK(PSCLK),   // Dynamic phase adjust clock input
  .PSEN(PSEN),     // Dynamic phase adjust enable input
  .PSINCDEC(PSINCDEC), // Dynamic phase adjust increment/decrement
  .RST(RST)        // DCM asynchronous reset input
);

  BUFG BUFG_clkfb(.I(clkfb), .O(clkfbbuf));
  BUFG BUFG_clkfx(.I(clkfx), .O(clkfxout));