// Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2019.2 (win64) Build 2708876 Wed Nov  6 21:40:23 MST 2019
// Date        : Sat Aug  1 19:36:15 2020
// Host        : DESKTOP-30BHVTT running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               C:/Users/TanZh/Documents/cpu/NCUT_1_hujiawei/soc_axi_func/run_vivado/mycpu_prj1/mycpu.srcs/sources_1/ip/dirty_ram/dirty_ram_stub.v
// Design      : dirty_ram
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a200tfbg676-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "dist_mem_gen_v8_0_13,Vivado 2019.2" *)
module dirty_ram(a, d, clk, we, spo)
/* synthesis syn_black_box black_box_pad_pin="a[7:0],d[0:0],clk,we,spo[0:0]" */;
  input [7:0]a;
  input [0:0]d;
  input clk;
  input we;
  output [0:0]spo;
endmodule
