`timescale 1ns / 1ps
`default_nettype wire

/*
 spec_mouse.v

 The mouse of the Specialist on the user PPI (Emu80 SpecMouse): a falling edge of PB0 gives the next byte
 of a packet on port A: 7F, 08 | buttons, dx, dy, dz. The deltas are -126..126, so they never equal the
 sync byte; what does not fit goes in the next packets. A program that stops polling for 1 s and comes
 back finds the movement and the presses dropped.

 The reports of kg_mcu: ms_x, ms_y deltas, ms_z the wheel (4 bits), ms_b the buttons, ms_upd toggles.
*/

module spec_mouse (
	input wire clk,
	input wire reset,
	input wire [7:0] ms_x,
	input wire [7:0] ms_y,
	input wire [3:0] ms_z,
	input wire [2:0] ms_b,
	input wire ms_upd,
	input wire strobe,
	output reg [7:0] data = 8'h7F
);

function [10:0] clamp;      // the accumulators, -768..768 (384 points x 2, as Emu80)
	input [10:0] v;
	clamp = (!v[10] && v > 11'd768) ? 11'd768 : (v[10] && v < -11'sd768) ? -11'sd768 : v;
endfunction

function [10:0] take;       // the part of an accumulator a packet takes
	input [10:0] v;
	take = (!v[10] && v > 11'd126) ? 11'd126 : (v[10] && v < -11'sd126) ? -11'sd126 : v;
endfunction

reg [10:0] ax = 11'd0, ay = 11'd0, az = 11'd0;
reg [2:0] pressed = 3'd0;
reg [7:0] p1 = 8'h08, p2 = 8'd0, p3 = 8'd0, p4 = 8'd0;
reg [2:0] idx = 3'd0;
reg upd_d = 1'b0, st_d = 1'b0;
reg [25:0] idle = 26'd0;
wire active = idle != 26'd40000000;
wire fall = st_d & ~strobe;
wire [10:0] tx = take(ax), ty = take(ay), tz = take(az);

always @(posedge clk) begin
	upd_d <= ms_upd;
	st_d <= strobe;
	if (active)
		idle <= idle + 26'd1;
	if (reset) begin
		ax <= 11'd0;
		ay <= 11'd0;
		az <= 11'd0;
		pressed <= 3'd0;
		idx <= 3'd0;
		data <= 8'h7F;
	end
	else if (fall) begin
		idle <= 26'd0;
		if (!active) begin
			ax <= 11'd0;
			ay <= 11'd0;
			az <= 11'd0;
			pressed <= ms_b;
		end
		idx <= idx == 3'd4 ? 3'd0 : idx + 3'd1;
		case (idx)
			3'd0: begin
				data <= 8'h7F;
				p1 <= { 5'b00001, ms_b | pressed };
				p2 <= tx[7:0];
				p3 <= ty[7:0];
				p4 <= tz[7:0];
				if (active) begin
					ax <= ax - tx;
					ay <= ay - ty;
					az <= az - tz;
				end
				pressed <= 3'd0;
			end
			3'd1: data <= p1;
			3'd2: data <= p2;
			3'd3: data <= p3;
			default: data <= p4;
		endcase
	end
	else if (ms_upd != upd_d) begin
		ax <= clamp(ax + { {3{ms_x[7]}}, ms_x });
		ay <= clamp(ay + { {3{ms_y[7]}}, ms_y });
		az <= clamp(az + { {7{ms_z[3]}}, ms_z });
		pressed <= pressed | ms_b;
	end
end

endmodule
