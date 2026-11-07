`timescale 1ns / 1ps
`default_nettype wire

// spec_system with a model of the SRAM (two lanes of 2M x 8, /OE low, as orion128 tb_boot), for sim_boot.
module tb_boot (
	input wire clk,
	input wire reset,
	input wire model_mx,
	input wire turbo,
	input wire [1:0] cmode,
	input wire autorun,
	input wire rom_active,
	input wire [21:0] rom_addr,
	input wire [7:0] rom_data,
	input wire rom_wr,
	input wire file_active,
	input wire [7:0] file_slot,
	input wire [31:0] file_addr,
	input wire [7:0] file_data,
	input wire file_wr,
	input wire [7:0] kb_scancode,
	input wire kb_scancode_upd,
	input wire [12:0] joy,
	output wire [23:0] rgb,
	output wire hs,
	output wire vs,
	output wire de,
	output wire beep,
	output wire mx,
	input wire [21:0] dbg_addr,
	output wire [7:0] dbg_q
);

wire [20:0] MA;
wire [15:0] MD;
wire [1:0] MWR_N;

spec_system sys (
	.clk(clk), .reset(reset), .model_mx(model_mx), .turbo(turbo), .cmode(cmode), .autorun(autorun),
	.rom_active(rom_active), .rom_addr(rom_addr), .rom_data(rom_data), .rom_wr(rom_wr),
	.file_active(file_active), .file_slot(file_slot), .file_addr(file_addr), .file_data(file_data), .file_wr(file_wr),
	.kb_scancode(kb_scancode), .kb_scancode_upd(kb_scancode_upd), .joy(joy),
	.rgb(rgb), .hs(hs), .vs(vs), .de(de),
	.tape_in(1'b1), .tape_out(), .beep(beep), .mx(mx),
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
