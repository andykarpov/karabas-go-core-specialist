`timescale 1ns / 1ps
`default_nettype wire

/*
 spec_video_576.v (orion_video_576.v of karabas-go-core-orion128, without its wide screens and modes)

 The screen of the Specialist as 720 x 576 at 50 Hz (CEA-861 576p: 27.0 MHz, 864 x 625, negative
 syncs), the rate of the original. The other output of the core, next to spec_video (800 x 600 at
 60 Hz).

 Two clocks: the SRAM is read on clk (40 MHz), the picture goes out on clk_pix (27 MHz). Each line
 of the Specialist (256, two output lines each, y 32..543) is fetched into one half of a line buffer
 while the other half shows: at the start of the output line before it, its 48 words (points in
 lane 0, colour in lane 1) are read through the video port of spec_sram.

 The width: 384 points, 3 output pixels for 2 (576, x 72..647). The colours are those of spec_video.

 mx and cmode are taken into clk_pix through two flip-flops: they change rarely.
*/
module spec_video_576 (
	input wire clk,
	input wire clk_pix,
	input wire en,                 // this output is on: else the fetch stops (the SRAM port is the other one's)
	input wire mx,
	input wire [1:0] cmode,

	output reg vid_req = 1'b0,
	output reg [20:0] vid_addr = 21'd0,
	input wire [15:0] vid_dout,
	input wire vid_valid,

	output reg [23:0] rgb = 24'd0,
	output reg hs = 1'b0,          // active high here (the top inverts them for the pins)
	output reg vs = 1'b0,
	output reg de = 1'b0
);

localparam H_TOTAL = 864, H_VISIBLE = 720, H_SYNC = 732, H_SYNC_END = 796;
localparam V_TOTAL = 625, V_VISIBLE = 576, V_SYNC = 581, V_SYNC_END = 586;
localparam V_TOP = 32;

// ------------------------------------------------------------------ clk_pix: the timing
reg [9:0] hcnt = 10'd0;
reg [9:0] vcnt = 10'd0;
reg line_tg = 1'b0;           // toggles at each new line, vcnt is that line
always @(posedge clk_pix) begin
	if (hcnt == H_TOTAL - 1) begin
		hcnt <= 10'd0;
		vcnt <= (vcnt == V_TOTAL - 1) ? 10'd0 : vcnt + 10'd1;
		line_tg <= ~line_tg;
	end
	else
		hcnt <= hcnt + 10'd1;
end

// ------------------------------------------------------------------ clk: the fetch
reg [2:0] tg_s = 3'd0;
always @(posedge clk)
	tg_s <= { tg_s[1:0], line_tg };
wire new_line = tg_s[2] != tg_s[1];

reg [9:0] next = 10'd0;
reg busy = 1'b0, waiting = 1'b0;
reg [6:0] fcol = 7'd0;
reg [7:0] frow = 8'd0;
reg buf_we = 1'b0;
reg [6:0] buf_wa = 7'd0;
reg [15:0] buf_wd = 16'd0;
wire [9:0] next_rel = next - V_TOP;

always @(posedge clk) begin
	vid_req <= 1'b0;
	buf_we <= 1'b0;
	if (!en) begin
		busy <= 1'b0;
		waiting <= 1'b0;
	end
	else if (new_line && !busy) begin
		// vcnt is stable for a line by now: the line after it
		next <= (vcnt == V_TOTAL - 1) ? 10'd0 : vcnt + 10'd1;
		busy <= 1'b1;
		waiting <= 1'b0;
		fcol <= 7'd0;
	end
	else if (busy && !waiting && fcol == 7'd0 && !(next >= V_TOP && next < V_TOP + 512 && next_rel[0] == 1'b0))
		busy <= 1'b0;             // not the first line of a row of the Orion: nothing to fetch
	else if (busy && !waiting) begin
		if (fcol == 7'd48)
			busy <= 1'b0;
		else begin
			frow <= next_rel[8:1];
			vid_req <= 1'b1;
			vid_addr <= { 5'd0, 16'h9000 + { 2'b00, fcol[5:0], next_rel[8:1] } };
			waiting <= 1'b1;
		end
	end
	else if (busy && vid_valid) begin
		buf_we <= 1'b1;
		buf_wa <= { frow[0], fcol[5:0] };
		buf_wd <= vid_dout;
		fcol <= fcol + 7'd1;
		waiting <= 1'b0;
	end
end

wire [15:0] buf_q;
reg [6:0] buf_ra = 7'd0;
kg_sdpram #(.DW(16), .AW(7)) lbuf (
	.clka(clk), .wea(buf_we), .addra(buf_wa), .dina(buf_wd),
	.clkb(clk_pix), .enb(1'b1), .addrb(buf_ra), .doutb(buf_q)
);

// ------------------------------------------------------------------ clk_pix: the picture
reg [2:0] m_s0 = 3'd0, m_s = 3'd0;
always @(posedge clk_pix) begin
	m_s0 <= { mx, cmode };
	m_s <= m_s0;
end
wire mx_s = m_s[2];
wire [1:0] cm_s = m_s[1:0];

wire [9:0] vrel = vcnt - V_TOP;
wire in_y = vcnt >= V_TOP && vcnt < V_TOP + 512;
localparam [9:0] XOFF = 10'd72;
localparam [3:0] CELL_LAST = 4'd11;

// the word of cell n is asked two clocks before it shows: the address at the start of the cell
// before (or at xoff - 3 for cell 0), the read a clock later
reg [3:0] ph = 4'd0;
reg [6:0] col = 7'd0;
reg run = 1'b0;
reg [7:0] pix = 8'd0, attr = 8'd0;
wire shift = ph == 4'd1 || ph == 4'd2 || ph == 4'd4 || ph == 4'd5 || ph == 4'd7 || ph == 4'd8 || ph == 4'd10;
wire [9:0] x_pre = XOFF - 10'd3;
wire [9:0] x_load = XOFF - 10'd1;
wire [9:0] vline_rel = vrel;
wire vline_in = in_y;

reg load_ok = 1'b0;
always @(posedge clk_pix) begin
	if (hcnt == x_pre) begin
		buf_ra <= { vline_rel[1], 6'd0 };
		load_ok <= vline_in;
	end
	if (hcnt == x_load) begin
		run <= load_ok;
		ph <= 4'd0;
		col <= 7'd1;
		pix <= load_ok ? buf_q[7:0] : 8'd0;
		attr <= load_ok ? buf_q[15:8] : 8'd0;
		buf_ra <= { buf_ra[6], 6'd1 };
	end
	else if (run && ph == CELL_LAST) begin
		ph <= 4'd0;
		if (col == 7'd48) begin
			run <= 1'b0;
			pix <= 8'd0;
			attr <= 8'd0;
		end
		else begin
			col <= col + 7'd1;
			pix <= buf_q[7:0];
			attr <= buf_q[15:8];
			buf_ra <= { buf_ra[6], col[5:0] + 6'd1 };
		end
	end
	else if (run) begin
		ph <= ph + 4'd1;
		if (shift)
			pix <= { pix[6:0], 1'b0 };
	end
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
	if (!run)
		color = 24'h000000;
	else if (mx_s)
		color = pix[7] ? pal16(attr[7:4]) : pal16(attr[3:0]);
	else if (!pix[7])
		color = 24'h000000;
	else case (cm_s)
		2'd0: color = pal8({ attr[7:6], attr[4] });
		2'd1: color = pal4(attr[7:6]);
		default: color = 24'hC0C0C0;
	endcase
end

// the point of a cycle is the pixel of its hcnt: the syncs and rgb one register later together
always @(posedge clk_pix) begin
	de <= hcnt < H_VISIBLE && vcnt < V_VISIBLE;
	hs <= hcnt >= H_SYNC && hcnt < H_SYNC_END;
	vs <= vcnt >= V_SYNC && vcnt < V_SYNC_END;
	rgb <= (hcnt < H_VISIBLE && vcnt < V_VISIBLE) ? color : 24'd0;
end

endmodule
