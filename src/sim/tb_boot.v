`timescale 1ns / 1ps
`default_nettype wire

// spec_system with a model of the SRAM (two lanes of 2M x 8, /OE low, as orion128 tb_boot), for sim_boot.
module tb_boot (
	input wire clk,
	input wire reset,
	input wire model_mx,
	input wire turbo,
	input wire rom_active,
	input wire [21:0] rom_addr,
	input wire [7:0] rom_data,
	input wire rom_wr,
	input wire [7:0] kb_pa_i,
	input wire [7:2] kb_pb_i,
	input wire [3:0] kb_pc_i,
	input wire kb_nr_n,
	output wire [7:0] kb_pa_o,
	output wire [7:0] kb_pb_o,
	output wire beep,
	output wire mx,
	input wire [21:0] dbg_addr,
	output wire [7:0] dbg_q
);

wire [20:0] MA;
wire [15:0] MD;
wire [1:0] MWR_N;

spec_system sys (
	.clk(clk), .reset(reset), .model_mx(model_mx), .turbo(turbo),
	.rom_active(rom_active), .rom_addr(rom_addr), .rom_data(rom_data), .rom_wr(rom_wr),
	.kb_pa_o(kb_pa_o), .kb_pb_o(kb_pb_o), .kb_pc_o(), .kb_pa_in(), .kb_pb_in(), .kb_pcl_in(),
	.kb_pa_i(kb_pa_i), .kb_pb_i(kb_pb_i), .kb_pc_i(kb_pc_i), .kb_nr_n(kb_nr_n), .tape_in(1'b1),
	.beep(beep), .tape_out(), .mx(mx),
	.vid_req(1'b0), .vid_addr(21'd0), .vid_dout(), .vid_valid(),
	.MA(MA), .MD(MD), .MWR_N(MWR_N)
);

reg [7:0] lo [0:2097151];
reg [7:0] hi [0:2097151];
assign MD = (MWR_N == 2'b11) ? { hi[MA], lo[MA] } : 16'bz;
assign dbg_q = dbg_addr[0] ? hi[dbg_addr[21:1]] : lo[dbg_addr[21:1]];

always @(posedge clk) begin
	if (!MWR_N[0]) lo[MA] <= MD[7:0];
	if (!MWR_N[1]) hi[MA] <= MD[15:8];
end

endmodule
