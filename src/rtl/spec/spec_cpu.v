`timescale 1ns / 1ps
`default_nettype wire

/*
 spec_cpu.v (orion_cpu.v of karabas-go-core-orion128)

 The processor as one bus: KR580VM80A (vm80a) or Z80 (T80pa, an option of phase 5), picked by cpu_z80,
 the other one is held in reset. Change cpu_z80 only during reset.

 KR580VM80A (vm80a, a cycle accurate model) on the clock of 40 MHz. One state is 20 clocks (2 MHz,
 the Specialist) or 10 clocks (4 MHz, turbo). vm80a takes its phases as enables of the fast clock:
 F1 and F2 do not overlap, with a gap of one clock between them, as on a real 8080.

 The SRAM answers a read within nine clocks; the 8080 takes the data two states after the address
 (40 / 20 clocks), so no wait is needed at either speed. hold (the READY pin) stops the CPU for a
 slow device: the FDD sync port FFF0 of the Specialist-MX. Change turbo at any time: it takes
 effect at the start of the next state.

 fetch: the status word of the cycle (D5, M1, on the data bus while SYNC) says that it fetches an
 opcode; it holds until the next SYNC. io: the cycle is an IN or OUT (D6, D4 of the status). The 8080
 shows them as a read and a write of the address {n, n}; so does this bus for the Z80 (mem_rd / mem_wr
 with io, addr {n, n}). The machine decides what an I/O cycle reaches.

 The Z80 takes the two edges of its clock as enables, 2 or 4 MHz; at 4 MHz an edge waits while a read is
 not ready (rd_ok). hold stops the edges.
*/

module spec_cpu (
	input wire clk,
	input wire reset,
	input wire cpu_z80,
	input wire turbo,            // 0 2 MHz, 1 4 MHz
	input wire rd_ok,
	input wire hold,

	output wire [15:0] addr,
	output wire [7:0] dout,
	input wire [7:0] din,
	output wire mem_rd,
	output wire mem_wr,
	output wire fetch,
	output wire io,
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

wire [15:0] a_80;
wire [7:0] do_80;
wire dbin, wr_n, sync, inte_80;
reg st_m1 = 1'b0, st_io = 1'b0;

vm80a_core cpu80 (
	.pin_clk(clk),
	.pin_f1(f1),
	.pin_f2(f2),
	.pin_reset(reset | cpu_z80),
	.pin_a(a_80),
	.pin_dout(do_80),
	.pin_din(din),
	.pin_aena(),
	.pin_dena(),
	.pin_hold(1'b0),
	.pin_hlda(),
	.pin_ready(~hold),
	.pin_wait(),
	.pin_int(1'b0),
	.pin_inte(inte_80),
	.pin_sync(sync),
	.pin_dbin(dbin),
	.pin_wr_n(wr_n)
);

always @(posedge clk)
	if (sync) begin
		st_m1 <= do_80[5];
		st_io <= do_80[6] | do_80[4];
	end

// ------------------------------------------------------------------ Z80
wire [15:0] a_z80;
wire [7:0] do_z80;
wire mreq_n, iorq_n, rd_z, wr_z, m1_n;

wire [4:0] per = turbo ? 5'd9 : 5'd19;
wire [4:0] mid = turbo ? 5'd4 : 5'd9;
wire z_rd = ~mreq_n & ~rd_z;
wire z_go = (!turbo || !z_rd || rd_ok) && !hold;
reg [4:0] zc = 5'd0;
wire z_edge = zc == per || zc == mid;
always @(posedge clk)
	if (!z_edge)
		zc <= zc + 5'd1;
	else if (z_go)
		zc <= (zc == per) ? 5'd0 : zc + 5'd1;

T80pa #(.Mode(0)) cpuz80 (
	.RESET_n(~reset & cpu_z80),
	.CLK(clk),
	.CEN_p(zc == per && z_go),
	.CEN_n(zc == mid && z_go),
	.WAIT_n(1'b1),
	.INT_n(1'b1),
	.NMI_n(1'b1),
	.BUSRQ_n(1'b1),
	.M1_n(m1_n),
	.MREQ_n(mreq_n),
	.IORQ_n(iorq_n),
	.RD_n(rd_z),
	.WR_n(wr_z),
	.RFSH_n(),
	.HALT_n(),
	.BUSAK_n(),
	.OUT0(1'b0),
	.A(a_z80),
	.DI(din),
	.DO(do_z80),
	.REG(),
	.DIRSet(1'b0),
	.DIR(212'd0)
);

wire z_io = ~iorq_n & m1_n;
assign addr = cpu_z80 ? (z_io ? { a_z80[7:0], a_z80[7:0] } : a_z80) : a_80;
assign dout = cpu_z80 ? do_z80 : do_80;
assign mem_rd = cpu_z80 ? (z_rd | (z_io & ~rd_z)) : dbin;
assign mem_wr = cpu_z80 ? ((~mreq_n | z_io) & ~wr_z) : ~wr_n;
assign fetch = cpu_z80 ? ~m1_n : st_m1;
assign io = cpu_z80 ? z_io : st_io;
assign inte = ~cpu_z80 & inte_80;

endmodule
