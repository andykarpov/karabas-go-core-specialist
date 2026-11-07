`timescale 1ns / 1ps
`default_nettype wire

/*
 spec_cpu.v (orion_cpu.v of karabas-go-core-orion128, the KR580VM80A only)

 KR580VM80A (vm80a, a cycle accurate model) on the clock of 40 MHz. One state is 20 clocks (2 MHz,
 the Specialist) or 10 clocks (4 MHz, turbo). vm80a takes its phases as enables of the fast clock:
 F1 and F2 do not overlap, with a gap of one clock between them, as on a real 8080.

 The SRAM answers a read within nine clocks; the 8080 takes the data two states after the address
 (40 / 20 clocks), so no wait is needed at either speed. hold (the READY pin) stops the CPU for a
 slow device: the FDD sync port FFF0 of the Specialist-MX. Change turbo at any time: it takes
 effect at the start of the next state.
*/

module spec_cpu (
	input wire clk,
	input wire reset,
	input wire turbo,            // 0 2 MHz, 1 4 MHz
	input wire hold,

	output wire [15:0] addr,
	output wire [7:0] dout,
	input wire [7:0] din,
	output wire mem_rd,
	output wire mem_wr,
	output wire inte
);

reg [4:0] cnt = 5'd0;
reg t4 = 1'b0;
reg f1 = 1'b0, f2 = 1'b0;
wire [4:0] last = t4 ? 5'd9 : 5'd19;
always @(posedge clk) begin
	if (cnt == last) begin
		cnt <= 5'd0;
		t4 <= turbo;
	end
	else
		cnt <= cnt + 5'd1;
	// 2 MHz: F1 0..3, F2 5..18; 4 MHz: F1 0..1, F2 3..8
	f1 <= t4 ? (cnt <= 5'd1) : (cnt <= 5'd3);
	f2 <= t4 ? (cnt >= 5'd3 && cnt <= 5'd8) : (cnt >= 5'd5 && cnt <= 5'd18);
end

wire dbin, wr_n;

vm80a_core cpu80 (
	.pin_clk(clk),
	.pin_f1(f1),
	.pin_f2(f2),
	.pin_reset(reset),
	.pin_a(addr),
	.pin_dout(dout),
	.pin_din(din),
	.pin_aena(),
	.pin_dena(),
	.pin_hold(1'b0),
	.pin_hlda(),
	.pin_ready(~hold),
	.pin_wait(),
	.pin_int(1'b0),
	.pin_inte(inte),
	.pin_sync(),
	.pin_dbin(dbin),
	.pin_wr_n(wr_n)
);

assign mem_rd = dbin;
assign mem_wr = ~wr_n;

endmodule
