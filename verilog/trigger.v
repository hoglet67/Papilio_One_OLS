//--------------------------------------------------------------------------------
// trigger.vhd
//
// Copyright (C) 2006 Michael Poppitz
// 
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin St, Fifth Floor, Boston, MA 02110, USA
//
//--------------------------------------------------------------------------------
//
// Details: http://www.sump.org/projects/analyzer/
//
// Complex 4 stage 32 channel trigger. 
//
// All commands are passed on to the stages. This file only maintains
// the global trigger level and it outputs the run condition if it is set
// by any of the stages.
// 
//--------------------------------------------------------------------------------
//
// 12/29/2010 - Ian Davis (IED) - Verilog version, changed to use LUT based 
//    masked comparisons, and other cleanups created - mygizmos.org
// 

`timescale 1ns/100ps

module trigger(
  clock, reset, 
  dataIn, validIn, 
  wrMask, wrValue, wrConfig, config_data,
  arm, demux_mode, 
  // outputs...
  capture, run);

input clock, reset;
input validIn;
input [31:0] dataIn;		// Channel data...
input [3:0] wrMask;		// Write trigger mask register
input [3:0] wrValue;		// Write trigger value register
input [3:0] wrConfig;		// Write trigger config register
input [31:0] config_data;	// Data to write into trigger config regs
input arm;
input demux_mode;
output capture;			// Store captured data in fifo.
output run;			// Tell controller when trigger hit.

reg capture, next_capture;
reg [1:0] levelReg, next_levelReg;

// if any of the stages set run, then capturing starts...
wire [3:0] stageRun;
wire run = |stageRun;


//
// IED - Shift register initialization handler...
//
// Much more space efficient in FPGA to compare this way.
//
// Instead of four seperate 32-bit value, 32-bit mask, and 32-bit comparison
// functions & all manner of flops & interconnect, each stage uses LUT table 
// lookups instead.
//
// Each LUT RAM evaluates 4-bits of input.  The RAM is programmed to 
// evaluate the original masked compare function, and is serially downloaded 
// by the following verilog.
//
//
// Background:
// ----------
// The original function was:  
//    hit = ((dataIn[31:0] ^ value[31:0]) & mask[31:0])==0;
//
//
// The following table shows the result for a single bit:
//    dataIn  value   mask    hit
//      x       x      0       1
//      0       0      1       1
//      0       1      1       0
//      1       0      1       0
//      1       1      1       1
//
// If a mask bit is zero, it always matches.   If one, then 
// the result of comparing dataIn & value matters.  If dataIn & 
// value match, the XOR function results in zero.  So if either
// the mask is zero, or the input matches value, you get a hit.
//
//
// New code
// --------
// To evaluate the dataIn, each address of the LUT RAM's evalutes:
//   What hit value should result assuming my address as input?
//
// In other words, LUT for dataIn[3:0] stores the following at given addresses:
//   LUT address 0 stores result of:  (4'h0 ^ value[3:0]) & mask[3:0])==0
//   LUT address 1 stores result of:  (4'h1 ^ value[3:0]) & mask[3:0])==0
//   LUT address 2 stores result of:  (4'h2 ^ value[3:0]) & mask[3:0])==0
//   LUT address 3 stores result of:  (4'h3 ^ value[3:0]) & mask[3:0])==0
//   LUT address 4 stores result of:  (4'h4 ^ value[3:0]) & mask[3:0])==0
//   etc...
//
// The LUT for dataIn[7:4] stores the following:
//   LUT address 0 stores result of:  (4'h0 ^ value[7:4]) & mask[7:4])==0
//   LUT address 1 stores result of:  (4'h1 ^ value[7:4]) & mask[7:4])==0
//   LUT address 2 stores result of:  (4'h2 ^ value[7:4]) & mask[7:4])==0
//   LUT address 3 stores result of:  (4'h3 ^ value[7:4]) & mask[7:4])==0
//   LUT address 4 stores result of:  (4'h4 ^ value[7:4]) & mask[7:4])==0
//   etc...
//
// Eight LUT's are needed to evalute all 32-bits of dataIn, so the 
// following verilog computes the LUT RAM data for all simultaneously.
//
//
// Result:
// ------
// It functionally does exactly the same thing as before.  Just uses 
// less FPGA.  Only requirement is the Client software on your PC issue 
// the value & mask's for each trigger stage in pairs.
//
reg [31:0] maskRegister, next_maskRegister;
reg [31:0] valueRegister, next_valueRegister;
reg [3:0] wrcount, next_wrcount;
reg [3:0] wrenb, next_wrenb;
reg [7:0] wrdata;

initial 
begin 
  wrcount=0;
  wrenb=4'b0;
end

always @ (posedge clock)
begin
  maskRegister = next_maskRegister;
  valueRegister = next_valueRegister;
  wrcount = next_wrcount;
  wrenb = next_wrenb;
end

always @*
begin
  next_wrcount = 0;

  // Capture data during mask write...
  next_maskRegister = (|wrMask) ? config_data : maskRegister;
  next_valueRegister = (|wrValue) ? config_data : valueRegister;

  // Do 16 writes when value register written...
  next_wrenb = wrenb | wrValue;
  if (|wrenb)
    begin
      next_wrcount = wrcount+1'b1;
      if (&wrcount) next_wrenb = 4'h0;
    end

  // Compute data for the 8 target LUT's...
  wrdata = {
    ~|((~wrcount^valueRegister[31:28])&maskRegister[31:28]),
    ~|((~wrcount^valueRegister[27:24])&maskRegister[27:24]),
    ~|((~wrcount^valueRegister[23:20])&maskRegister[23:20]),
    ~|((~wrcount^valueRegister[19:16])&maskRegister[19:16]),
    ~|((~wrcount^valueRegister[15:12])&maskRegister[15:12]),
    ~|((~wrcount^valueRegister[11:8])&maskRegister[11:8]),
    ~|((~wrcount^valueRegister[7:4])&maskRegister[7:4]),
    ~|((~wrcount^valueRegister[3:0])&maskRegister[3:0])};

  if (reset)
    begin
      next_wrcount = 0;
      next_wrenb = 4'h0;
    end
end


//
// Instantiate stages...
//
wire [3:0] stageMatch;
stage stage0 (
  .clock(clock), .reset(reset), .dataIn(dataIn), .validIn(validIn), 
//  .wrMask(wrMask[0]), .wrValue(wrValue[0]), 
  .wrenb(wrenb[0]), .din(wrdata),
  .wrConfig(wrConfig[0]), .config_data(config_data),
  .arm(arm), .level(levelReg), .demux_mode(demux_mode),
  .run(stageRun[0]), .match(stageMatch[0]));

stage stage1 (
  .clock(clock), .reset(reset), .dataIn(dataIn), .validIn(validIn), 
//  .wrMask(wrMask[1]), .wrValue(wrValue[1]), 
  .wrenb(wrenb[1]), .din(wrdata),
  .wrConfig(wrConfig[1]), .config_data(config_data),
  .arm(arm), .level(levelReg), .demux_mode(demux_mode),
  .run(stageRun[1]), .match(stageMatch[1]));

stage stage2 (
  .clock(clock), .reset(reset), .dataIn(dataIn), .validIn(validIn), 
//  .wrMask(wrMask[2]), .wrValue(wrValue[2]), 
  .wrenb(wrenb[2]), .din(wrdata),
  .wrConfig(wrConfig[2]), .config_data(config_data),
  .arm(arm), .level(levelReg), .demux_mode(demux_mode),
  .run(stageRun[2]), .match(stageMatch[2]));

stage stage3 (
  .clock(clock), .reset(reset), .dataIn(dataIn), .validIn(validIn), 
//  .wrMask(wrMask[3]), .wrValue(wrValue[3]), 
  .wrenb(wrenb[3]), .din(wrdata),
  .wrConfig(wrConfig[3]), .config_data(config_data),
  .arm(arm), .level(levelReg), .demux_mode(demux_mode),
  .run(stageRun[3]), .match(stageMatch[3]));


//
// Increase level on match (on any level?!)...
//
initial levelReg = 2'b00;
always @(posedge clock or posedge reset) 
begin : P2
  if (reset) 
    begin
      capture = 1'b0;
      levelReg = 2'b00;
    end
  else 
    begin
      capture = next_capture;
      levelReg = next_levelReg;
    end
end

always @*
begin
  #1;
  next_capture = arm | capture;
  next_levelReg = levelReg;
  if (|stageMatch) next_levelReg = levelReg + 1;
end
endmodule


