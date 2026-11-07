`timescale 1ns / 1ps
`default_nettype wire

/*
 spec_kbd.v

 The PS/2 set 2 scancodes of kg_mcu as the keyboard of the Specialist: a matrix of 12 columns
 (PA0..7, PC0..3 of the keyboard PPI) by 6 rows (PB2..7), and the key NR (Shift) on PB1, all
 active low. The matrix is scanned both ways (Emu80 SpecKeyboard): with columns driven low the
 rows read the keys of those columns, with rows driven low the columns read the keys of those
 rows. A port in input mode drives FF (spec_ppi), so it selects nothing.

 The layout is that of Emu80 (KbdLayout / SpecKbdLayout, QWERTY mode): a host key gives the
 Specialist key at its place, letters and digits as written, = is :, ' is ^, ` is @, Ctrl is PV
 (repeat), PgUp is STR (clear; F12 of Emu80 is the Reset of the OSD here), PgDn and End are PS (line feed), Insert and Caps Lock are
 RUS/LAT, Shift is NR. The MX (RAMFOS) moves F1..F10, Esc and Tab (m_keyMatrixMx); mx changes only
 during reset.

 joy: a joystick as keys: the arrows, A Space, B and Start Enter (as core-orion128).
*/

module spec_kbd (
	input wire clk,
	input wire reset,
	input wire mx,
	input wire [7:0] scancode,
	input wire scancode_upd,    // toggles with each byte
	input wire [12:0] joy,      // up, down, left, right, start, A, B in bits 1..7

	input wire [7:0] pa_o,
	input wire [3:0] pc_o,
	input wire [7:2] pb_o,
	output wire [7:0] pa_i,
	output wire [3:0] pc_i,
	output wire [7:2] pb_i,
	output wire nr_n
);

// a key: { valid, column, row }
function [7:0] k;
	input [3:0] c;
	input [2:0] r;
	k = { 1'b1, c, r };
endfunction

reg ext = 1'b0, rel = 1'b0;
reg [7:0] pos;
always @* begin
	case ({ ext, scancode })
		// row 0
		9'h05A, 9'h15A: pos = k(4'd0, 3'd0);     // Enter: VK
		9'h17A, 9'h169: pos = k(4'd1, 3'd0);     // PgDn, End: PS
		9'h174: pos = k(4'd2, 3'd0);             // Right
		9'h014, 9'h114: pos = mx ? 8'd0 : k(4'd3, 3'd0);  // Ctrl: PV
		9'h16B: pos = k(4'd4, 3'd0);             // Left
		9'h029: pos = k(4'd5, 3'd0);             // Space
		9'h076: pos = mx ? k(4'd11, 3'd5) : k(4'd6, 3'd0);  // Esc
		9'h00D: pos = mx ? k(4'd3, 3'd0) : k(4'd7, 3'd0);   // Tab
		9'h172: pos = k(4'd8, 3'd0);             // Down
		9'h175: pos = k(4'd9, 3'd0);             // Up
		9'h16C: pos = k(4'd10, 3'd0);            // Home
		9'h058, 9'h170: pos = k(4'd11, 3'd0);    // Caps Lock, Insert: RUS/LAT
		// row 1
		9'h066: pos = k(4'd0, 3'd1);             // Backspace
		9'h04A, 9'h14A: pos = k(4'd1, 3'd1);     // /
		9'h041: pos = k(4'd2, 3'd1);             // ,
		9'h00E: pos = k(4'd3, 3'd1);             // `: @
		9'h032: pos = k(4'd4, 3'd1);             // B
		9'h022: pos = k(4'd5, 3'd1);             // X
		9'h02C: pos = k(4'd6, 3'd1);             // T
		9'h043: pos = k(4'd7, 3'd1);             // I
		9'h03A: pos = k(4'd8, 3'd1);             // M
		9'h01B: pos = k(4'd9, 3'd1);             // S
		9'h052: pos = k(4'd10, 3'd1);            // ': ^
		9'h015: pos = k(4'd11, 3'd1);            // Q
		// row 2
		9'h049, 9'h071: pos = k(4'd0, 3'd2);     // .
		9'h05D: pos = k(4'd1, 3'd2);             // backslash
		9'h02A: pos = k(4'd2, 3'd2);             // V
		9'h023: pos = k(4'd3, 3'd2);             // D
		9'h04B: pos = k(4'd4, 3'd2);             // L
		9'h044: pos = k(4'd5, 3'd2);             // O
		9'h02D: pos = k(4'd6, 3'd2);             // R
		9'h04D: pos = k(4'd7, 3'd2);             // P
		9'h01C: pos = k(4'd8, 3'd2);             // A
		9'h01D: pos = k(4'd9, 3'd2);             // W
		9'h035: pos = k(4'd10, 3'd2);            // Y
		9'h02B: pos = k(4'd11, 3'd2);            // F
		// row 3
		9'h055: pos = k(4'd0, 3'd3);             // =: :
		9'h033: pos = k(4'd1, 3'd3);             // H
		9'h01A: pos = k(4'd2, 3'd3);             // Z
		9'h05B: pos = k(4'd3, 3'd3);             // ]
		9'h054: pos = k(4'd4, 3'd3);             // [
		9'h034: pos = k(4'd5, 3'd3);             // G
		9'h031: pos = k(4'd6, 3'd3);             // N
		9'h024: pos = k(4'd7, 3'd3);             // E
		9'h042: pos = k(4'd8, 3'd3);             // K
		9'h03C: pos = k(4'd9, 3'd3);             // U
		9'h021: pos = k(4'd10, 3'd3);            // C
		9'h03B: pos = k(4'd11, 3'd3);            // J
		// row 4
		9'h04E, 9'h07B: pos = k(4'd0, 3'd4);     // -
		9'h045, 9'h070: pos = k(4'd1, 3'd4);     // 0
		9'h046, 9'h07D: pos = k(4'd2, 3'd4);     // 9
		9'h03E, 9'h075: pos = k(4'd3, 3'd4);     // 8
		9'h03D, 9'h06C: pos = k(4'd4, 3'd4);     // 7
		9'h036, 9'h074: pos = k(4'd5, 3'd4);     // 6
		9'h02E, 9'h073: pos = k(4'd6, 3'd4);     // 5
		9'h025, 9'h06B: pos = k(4'd7, 3'd4);     // 4
		9'h026, 9'h07A: pos = k(4'd8, 3'd4);     // 3
		9'h01E, 9'h072: pos = k(4'd9, 3'd4);     // 2
		9'h016, 9'h069: pos = k(4'd10, 3'd4);    // 1
		9'h04C: pos = k(4'd11, 3'd4);            // ;
		// row 5: STR and the function keys
		9'h17D: pos = k(4'd0, 3'd5);             // PgUp: STR
		9'h005: pos = mx ? k(4'd9, 3'd5) : k(4'd11, 3'd5);  // F1
		9'h006: pos = mx ? k(4'd8, 3'd5) : k(4'd10, 3'd5);  // F2
		9'h004: pos = mx ? k(4'd7, 3'd5) : k(4'd9, 3'd5);   // F3
		9'h00C: pos = mx ? k(4'd6, 3'd5) : k(4'd8, 3'd5);   // F4
		9'h003: pos = mx ? k(4'd5, 3'd5) : k(4'd7, 3'd5);   // F5
		9'h00B: pos = mx ? k(4'd4, 3'd5) : k(4'd6, 3'd5);   // F6
		9'h083: pos = mx ? k(4'd3, 3'd5) : k(4'd5, 3'd5);   // F7
		9'h00A: pos = mx ? k(4'd2, 3'd5) : k(4'd4, 3'd5);   // F8
		9'h001: pos = mx ? k(4'd1, 3'd5) : k(4'd3, 3'd5);   // F9
		9'h009: pos = mx ? k(4'd10, 3'd5) : k(4'd2, 3'd5);  // F10
		9'h078: pos = mx ? 8'd0 : k(4'd1, 3'd5);            // F11
		default: pos = 8'd0;
	endcase
end

reg [127:0] km = 128'd0;   // { column, row }
reg nr = 1'b0;
reg upd_d = 1'b0;
always @(posedge clk) begin
	upd_d <= scancode_upd;
	if (reset) begin
		ext <= 1'b0;
		rel <= 1'b0;
		km <= 128'd0;
		nr <= 1'b0;
	end
	else if (scancode_upd != upd_d) begin
		if (scancode == 8'hE0)
			ext <= 1'b1;
		else if (scancode == 8'hF0)
			rel <= 1'b1;
		else begin
			ext <= 1'b0;
			rel <= 1'b0;
			if ({ ext, scancode } == 9'h012 || { ext, scancode } == 9'h059)
				nr <= ~rel;
			else if (pos[7])
				km[pos[6:0]] <= ~rel;
		end
	end
end

// the joystick: pressed while held, on top of the keys
wire j_up = joy[1], j_down = joy[2], j_left = joy[3], j_right = joy[4];
wire j_space = joy[6], j_enter = joy[5] | joy[7];
wire [127:0] kj = km | ({ 127'd0, j_enter } << { 4'd0, 3'd0 }) | ({ 127'd0, j_right } << { 4'd2, 3'd0 }) |
                  ({ 127'd0, j_left } << { 4'd4, 3'd0 }) | ({ 127'd0, j_space } << { 4'd5, 3'd0 }) |
                  ({ 127'd0, j_down } << { 4'd8, 3'd0 }) | ({ 127'd0, j_up } << { 4'd9, 3'd0 });

wire [11:0] sel_col = ~{ pc_o, pa_o };
wire [5:0] sel_row = ~pb_o;

reg [5:0] rows;
reg [11:0] cols;
integer c, r;
always @* begin
	rows = 6'd0;
	cols = 12'd0;
	for (c = 0; c < 12; c = c + 1)
		for (r = 0; r < 6; r = r + 1)
			if (kj[c * 8 + r]) begin
				if (sel_col[c]) rows[r] = 1'b1;
				if (sel_row[r]) cols[c] = 1'b1;
			end
end

assign pb_i = ~rows;
assign pa_i = ~cols[7:0];
assign pc_i = ~cols[11:8];
assign nr_n = ~nr;

endmodule
