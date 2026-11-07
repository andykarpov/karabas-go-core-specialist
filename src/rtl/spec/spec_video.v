`timescale 1ns / 1ps
`default_nettype wire

/*
 spec_video.v (orion_video.v of karabas-go-core-orion128, without its wide screens and modes)

 The screen of the Specialist read straight from the SRAM as VESA 800 x 600 at 60 Hz (40.0 MHz,
 1056 x 628, positive syncs), no frame buffer. A point is 2 x 2 output pixels: the picture of
 384 x 256 is 768 x 512 in the middle (x 16..783, y 44..555), the rest is black.

 The screen is 9000-BFFF of the main RAM, by columns: the byte of column c (0..47), row r is at
 9000 + c * 256 + r, its high bit the left point. A cell of 8 points is 16 clocks. Its 16-bit
 read (the points in lane 0, their colour in lane 1, spec_system) is asked one cell before it
 shows, and the word is loaded into the shift register at the start of the cell. spec_sram
 answers within 6 clocks.

 Colours, the palettes of Emu80 (SpecRenderer):
   mx: points D7..4 of the colour byte, background D3..0, 16 colours
   the Specialist: background black, points by cmode: 0 eight colours by (D7, D6, D4) (the bits of
   port C written with the byte), 1 four colours by (D7, D6), 2 mono (light grey)
*/

module spec_video (
	input wire clk,
	input wire mx,
	input wire [1:0] cmode,

	output wire vid_req,
	output wire [20:0] vid_addr,
	input wire [15:0] vid_dout,
	input wire vid_valid,

	output reg [23:0] rgb = 24'd0,
	output reg hs = 1'b0,
	output reg vs = 1'b0,
	output reg de = 1'b0
);

parameter H_TOTAL = 1056, H_VISIBLE = 800, H_SYNC = 840, H_SYNC_END = 968;
parameter V_TOTAL = 628, V_VISIBLE = 600, V_SYNC = 601, V_SYNC_END = 605;
parameter V_TOP = 44;     // the first line of the picture

reg [10:0] hcnt = 11'd0;
reg [9:0] vcnt = 10'd0;
always @(posedge clk) begin
	if (hcnt == H_TOTAL - 1) begin
		hcnt <= 11'd0;
		vcnt <= (vcnt == V_TOTAL - 1) ? 10'd0 : vcnt + 10'd1;
	end
	else
		hcnt <= hcnt + 11'd1;
end

wire [9:0] vrel = vcnt - V_TOP;
wire in_y = vcnt >= V_TOP && vcnt < V_TOP + 512;
wire [7:0] row = vrel[8:1];

reg [3:0] ph = 4'd0;
reg [5:0] col = 6'd0;
reg run = 1'b0;
wire line_start = hcnt == 11'd0;
always @(posedge clk) begin
	if (line_start) begin
		run <= in_y;
		ph <= 4'd0;
		col <= 6'd0;
	end
	else if (ph == 4'd15) begin
		ph <= 4'd0;
		if (run) begin
			col <= col + 6'd1;
			if (col == 6'd48)
				run <= 1'b0;
		end
	end
	else
		ph <= ph + 4'd1;
end

wire cell_start = ph == 4'd0;
wire live = run || (line_start && in_y);
wire [5:0] col_now = line_start ? 6'd0 : col;

wire [15:0] a = 16'h9000 + { 2'b00, col_now, row };
assign vid_req = live && cell_start && col_now < 6'd48;
assign vid_addr = { 5'd0, a };

reg [15:0] hold = 16'd0;
always @(posedge clk)
	if (vid_valid)
		hold <= vid_dout;

// the word asked in cell n shows in cell n + 1
wire show = live && col_now != 6'd0;
wire shift = ph[0] == 1'b0 && ph != 4'd0;
reg [7:0] pix = 8'd0, attr = 8'd0;
always @(posedge clk) begin
	if (cell_start) begin
		pix <= show ? hold[7:0] : 8'd0;
		attr <= show ? hold[15:8] : 8'd0;
	end
	else if (shift)
		pix <= { pix[6:0], 1'b0 };
end

function [23:0] pal16;
	input [3:0] i;
	case (i)
		4'h0: pal16 = 24'h000000;
		4'h1: pal16 = 24'h0000C0;
		4'h2: pal16 = 24'h00C000;
		4'h3: pal16 = 24'h00C0C0;
		4'h4: pal16 = 24'hC00000;
		4'h5: pal16 = 24'hC000C0;
		4'h6: pal16 = 24'hC0C000;
		4'h7: pal16 = 24'hC0C0C0;
		4'h8: pal16 = 24'h808080;
		4'h9: pal16 = 24'h0000FF;
		4'hA: pal16 = 24'h00FF00;
		4'hB: pal16 = 24'h00FFFF;
		4'hC: pal16 = 24'hFF0000;
		4'hD: pal16 = 24'hFF00FF;
		4'hE: pal16 = 24'hFFFF00;
		default: pal16 = 24'hFFFFFF;
	endcase
endfunction

function [23:0] pal8;
	input [2:0] i;
	case (i)
		3'd0: pal8 = 24'hFFFFFF;
		3'd1: pal8 = 24'hFFFF00;
		3'd2: pal8 = 24'hFF00FF;
		3'd3: pal8 = 24'hFF0000;
		3'd4: pal8 = 24'h00FFFF;
		3'd5: pal8 = 24'h00FF00;
		3'd6: pal8 = 24'h0000FF;
		default: pal8 = 24'h000000;
	endcase
endfunction

function [23:0] pal4;
	input [1:0] i;
	case (i)
		2'd0: pal4 = 24'hFFFFFF;
		2'd1: pal4 = 24'hFF0000;
		2'd2: pal4 = 24'h00FF00;
		default: pal4 = 24'h0000FF;
	endcase
endfunction

reg [23:0] color;
always @* begin
	if (mx)
		color = pix[7] ? pal16(attr[7:4]) : pal16(attr[3:0]);
	else if (!pix[7])
		color = 24'h000000;
	else case (cmode)
		2'd0: color = pal8({ attr[7:6], attr[4] });
		2'd1: color = pal4(attr[7:6]);
		default: color = 24'hC0C0C0;
	endcase
end

// the pixel of hcnt is out two clocks later: the shift register, then rgb
reg de_d = 1'b0, hs_d = 1'b0, vs_d = 1'b0;
reg in_pic = 1'b0;
always @(posedge clk) begin
	de_d <= hcnt < H_VISIBLE && vcnt < V_VISIBLE;
	hs_d <= hcnt >= H_SYNC && hcnt < H_SYNC_END;
	vs_d <= vcnt >= V_SYNC && vcnt < V_SYNC_END;
	in_pic <= show;
	de <= de_d;
	hs <= hs_d;
	vs <= vs_d;
	rgb <= in_pic ? color : 24'd0;
end

endmodule
