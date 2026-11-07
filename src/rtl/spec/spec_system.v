`timescale 1ns / 1ps
`default_nettype wire

/*
 spec_system.v

 The Specialist and the Specialist-MX: the processor, the memory maps, the ports, the SRAM, the
 video and the keyboard, on one clock of 40 MHz. docs/HARDWARE.md has the maps. The structure is
 that of orion_system of karabas-go-core-orion128. The FDC of the MX comes in phase 3.

 The sound: the Specialist has the beeper on PC5 of the keyboard PPI. The MX has the 8253 at FFEC
 (KF8253 of kitune-san, MIT, from karabas-go-core-pcxt) on 2 MHz: channels 0 and 1 count it,
 channel 2 counts the output of channel 1 (Emu80 SpecMxPit8253SoundSource; Sorgelig clocks channel
 0 by it instead, docs/BACKLOG.md); the sound is OUT0 or OUT2, silenced while PC5 is 1 (the gate of
 Emu80), and the tape output PC7 is heard too (not muted in Emu80).

 SRAM (a byte address of 22 bits, spec_sram; a 64 KB page is {bank, a[15:0], lane}):
   000000  the main RAM: lane 0 the bytes, lane 1 the colour of each byte of the screen
           (9000-BFFF), so the video reads points and colour in one access
   020000  the RAM disk of the MX, disks 0..7 = banks 1..4, both lanes
   200000  the Monitor of the Specialist (up to 12 KB, at C000-EFFF), bytes in a row
   210000  the ROM of the MX (48 KB, at 0000-BFFF in the ROM page), bytes in a row
 The ROMs arrive by the ROM loader of the mcu, files by the FL items (spec_loader); the machine is
 in reset while either loads.

 The Specialist starts at 0000: after reset its Monitor answers every read (its first bytes are a
 jump to C003), until the first read at C000-FFFF. The MX starts in its ROM page.

 A .rks file starts as Emu80 runs it: after the load the machine leaves reset, its Monitor runs for
 200 ms (it sets up the PPI and its variables), then the next opcode fetch reads JMP start instead
 of the memory (autorun). The MX runs RAMFOS for those 200 ms, and the injected jump also selects
 the RAM page, where the file is (the main RAM, as the core of Sorgelig loads it).

 mx (the model) is taken during reset only.
*/

module spec_system (
	input wire clk,
	input wire reset,
	input wire model_mx,         // 0 the Specialist, 1 the Specialist-MX
	input wire turbo,            // the CPU at 4 MHz
	input wire [1:0] cmode,      // the colours of the Specialist: 8, 4, mono
	input wire autorun,          // start a .rks after its load

	// the ROM loader and the file loader of the mcu
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

	input wire tape_in,
	output wire tape_out,        // PC7
	output wire sound,           // the Specialist: the beeper PC5; the MX: the 8253 gated by PC5
	output reg mx = 1'b0,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N
);

wire run_reset = reset | rom_active | file_active;

always @(posedge clk)
	if (run_reset)
		mx <= model_mx;

wire [15:0] a;
wire [7:0] cpu_do;
reg [7:0] cpu_di;
wire mem_rd, mem_wr, fetch;

spec_cpu cpu (
	.clk(clk),
	.reset(run_reset),
	.turbo(turbo),
	.hold(1'b0),
	.addr(a),
	.dout(cpu_do),
	.din(cpu_di),
	.mem_rd(mem_rd),
	.mem_wr(mem_wr),
	.fetch(fetch),
	.inte()
);

reg wr_d = 1'b0, rd_d = 1'b0;
always @(posedge clk) begin
	wr_d <= mem_wr;
	rd_d <= mem_rd;
end
wire wr_p = mem_wr & ~wr_d;   // one clock at the start of a write
wire rd_end = rd_d & ~mem_rd; // the clock after a read

// ------------------------------------------------------------------ decoding
// the Specialist
wire o_rom = a[15:14] == 2'b11 && a[15:12] != 4'hF;   // C000-EFFF
wire o_usr = a[15:11] == 5'b11110;                    // F000-F7FF
wire o_kbd = a[15:11] == 5'b11111;                    // F800-FFFF

// the MX: FFC0-FFDF the system RAM (the main RAM there), FFE0-FFFF the devices by A4..A2
wire m_dev = a[15:5] == 11'b11111111111;
wire m_sys = a[15:5] == 11'b11111111110;
wire [2:0] m_reg = a[4:2];
wire m_kbd = m_dev && m_reg == 3'd0;   // FFE0
wire m_usr = m_dev && m_reg == 3'd1;   // FFE4
wire m_pit = m_dev && m_reg == 3'd3;   // FFEC
wire m_col = m_dev && m_reg == 3'd6;   // FFF8
wire m_pag = m_dev && m_reg == 3'd7;   // FFFC

wire inj_page;
wire [7:0] pit_do;
wire pit_out0, pit_out1, pit_out2;
reg [1:0] mpage = 2'd3;      // 0 RAM, 1 RAM disk, 2 / 3 ROM (written by the address FFFC..FFFF)
reg [2:0] mdisk = 3'd0;
reg [7:0] mcolor = 8'h70;    // FFF8: D7..4 points, D3..0 background
always @(posedge clk) begin
	if (run_reset) begin
		mpage <= 2'd3;
		mdisk <= 3'd0;
		mcolor <= 8'h70;
	end
	else if (inj_page)
		mpage <= 2'd0;
	else if (wr_p && mx) begin
		if (m_pag) begin
			mpage <= a[1:0];
			if (a[1:0] == 2'd1)
				mdisk <= cpu_do[2:0];
		end
		if (m_col)
			mcolor <= cpu_do;
	end
end

// the Monitor everywhere after reset (the Specialist)
reg ipl = 1'b1;
always @(posedge clk)
	if (run_reset)
		ipl <= 1'b1;
	else if (mem_rd && a[15:14] == 2'b11)
		ipl <= 1'b0;

wire sel_kbd = mx ? m_kbd : o_kbd;
wire sel_usr = mx ? m_usr : o_usr;
wire sel_dev = mx ? m_dev : (o_usr | o_kbd);

// ------------------------------------------------------------------ the PPIs and the keyboard
wire [7:0] kbd_do, usr_do, kb_pc, kb_pa, kb_pb, kb_pa_i;
wire [3:0] kb_pc_i;
wire [7:2] kb_pb_i;
wire kb_nr_n;

spec_ppi ppi_kbd (
	.clk(clk), .reset(run_reset), .a(a[1:0]), .wr(wr_p & sel_kbd), .din(cpu_do), .dout(kbd_do),
	.pa_i(kb_pa_i), .pb_i({ kb_pb_i, kb_nr_n, tape_in }), .pc_i({ 4'hF, kb_pc_i }),
	.pa_in(), .pb_in(), .pcl_in(),
	.pa_o(kb_pa), .pb_o(kb_pb), .pc_o(kb_pc)
);
assign tape_out = kb_pc[7];

spec_kbd kbd (
	.clk(clk),
	.reset(reset),
	.mx(mx),
	.scancode(kb_scancode),
	.scancode_upd(kb_scancode_upd),
	.joy(joy),
	.pa_o(kb_pa),
	.pc_o(kb_pc[3:0]),
	.pb_o(kb_pb[7:2]),
	.pa_i(kb_pa_i),
	.pc_i(kb_pc_i),
	.pb_i(kb_pb_i),
	.nr_n(kb_nr_n)
);

// the user port, nothing on it yet
spec_ppi ppi_usr (
	.clk(clk), .reset(run_reset), .a(a[1:0]), .wr(wr_p & sel_usr), .din(cpu_do), .dout(usr_do),
	.pa_i(8'hFF), .pb_i(8'hFF), .pc_i(8'hFF),
	.pa_in(), .pb_in(), .pcl_in(),
	.pa_o(), .pb_o(), .pc_o()
);

// ------------------------------------------------------------------ the memory
wire [21:0] ram_addr = { 5'd0, a, 1'b0 };
wire [4:0] disk_bank = { 3'd0, mdisk[2:1] } + 5'd1;
wire [21:0] disk_addr = { disk_bank, a, mdisk[0] };

// what a read or a write at a reaches
reg sel_rom;     // a ROM byte at rom_off
reg sel_ram;     // the main RAM
reg sel_disk;    // the RAM disk
reg [21:0] rom_off;
always @* begin
	sel_rom = 1'b0;
	sel_ram = 1'b0;
	sel_disk = 1'b0;
	rom_off = { 8'b10000000, a[13:0] };          // 200000 + (a - C000), and 0000.. while ipl
	if (!mx) begin
		if (o_rom || (ipl && !mem_wr))
			sel_rom = 1'b1;
		else if (!sel_dev)
			sel_ram = 1'b1;
	end
	else begin
		rom_off = { 6'b100001, a };               // 210000 + a
		if (m_dev)
			;
		else if (m_sys)
			sel_ram = 1'b1;
		else case (mpage)
			2'd0: sel_ram = 1'b1;
			2'd1: sel_disk = 1'b1;
			default:
				if (a[15:14] != 2'b11)
					sel_rom = 1'b1;
				else
					sel_ram = 1'b1;
		endcase
	end
end

// a write to the screen stores the colour of its byte: the Specialist takes PC7, PC6, PC4 of the
// keyboard PPI (as written), the MX its register FFF8
wire scr = a[15:12] >= 4'h9 && a[15:14] == 2'b10;    // 9000-BFFF
wire [7:0] cur_color = mx ? mcolor : (kb_pc & 8'hD0);

wire [21:0] sram_addr = sel_rom ? rom_off : sel_disk ? disk_addr : ram_addr;
wire sram_we = mem_wr && (sel_ram || sel_disk);
wire sram_wr16 = sel_ram && scr;
wire [7:0] sram_do;

// ------------------------------------------------------------------ autorun of a .rks
wire [15:0] rks_start;
wire rks_ok;
reg file_d = 1'b0;
reg [22:0] run_wait = 23'd0;   // 200 ms of the Monitor
reg run_pend = 1'b0, run_arm = 1'b0;
reg [1:0] inj = 2'd0;          // 1 the opcode, 2 / 3 the address bytes
always @(posedge clk) begin
	file_d <= file_active;
	if (reset) begin
		run_pend <= 1'b0;
		run_arm <= 1'b0;
		inj <= 2'd0;
	end
	else if (file_d && !file_active) begin
		run_pend <= autorun && rks_ok && file_slot == 8'd1;
		run_arm <= 1'b0;
		inj <= 2'd0;
		run_wait <= 23'd7999999;
	end
	else if (run_pend) begin
		if (run_wait == 23'd0) begin
			run_pend <= 1'b0;
			run_arm <= 1'b1;
		end
		else
			run_wait <= run_wait - 23'd1;
	end
	else if (run_arm && mem_rd && fetch) begin
		run_arm <= 1'b0;
		inj <= 2'd1;
	end
	else if (inj != 2'd0 && rd_end)
		inj <= inj == 2'd3 ? 2'd0 : inj + 2'd1;
end

assign inj_page = run_arm && mem_rd && fetch && mx;

always @* begin
	cpu_di = 8'hFF;
	if (inj == 2'd1) cpu_di = 8'hC3;
	else if (inj == 2'd2) cpu_di = rks_start[7:0];
	else if (inj == 2'd3) cpu_di = rks_start[15:8];
	else if (sel_kbd) cpu_di = kbd_do;
	else if (mx && m_pit) cpu_di = pit_do;
	else if (sel_usr) cpu_di = usr_do;
	else if (sel_rom || sel_ram || sel_disk) cpu_di = sram_do;
end

// ------------------------------------------------------------------ the 8253 of the MX
reg [3:0] pit_div = 4'd0;
reg pit_clk = 1'b0;           // 2 MHz: a falling edge every 20 clocks
always @(posedge clk)
	if (pit_div == 4'd9) begin
		pit_div <= 4'd0;
		pit_clk <= ~pit_clk;
	end
	else
		pit_div <= pit_div + 4'd1;

KF8253 pit (
	.clock(clk),
	.reset(run_reset),
	.chip_select_n(~(mx && m_pit)),
	.read_enable_n(~mem_rd),
	.write_enable_n(~mem_wr),
	.address(a[1:0]),
	.data_bus_in(cpu_do),
	.data_bus_out(pit_do),
	.counter_0_clock(pit_clk),
	.counter_0_gate(1'b1),
	.counter_0_out(pit_out0),
	.counter_1_clock(pit_clk),
	.counter_1_gate(1'b1),
	.counter_1_out(pit_out1),
	.counter_2_clock(pit_out1),
	.counter_2_gate(1'b1),
	.counter_2_out(pit_out2)
);

assign sound = mx ? ~kb_pc[5] & (pit_out0 | pit_out2) : kb_pc[5];

// ------------------------------------------------------------------ the loaders, the SRAM, the video
wire aux_req, aux_ack;
wire [21:0] aux_addr;
wire [7:0] aux_din;

spec_loader loader (
	.clk(clk),
	.rom_active(rom_active),
	.rom_addr(rom_addr),
	.rom_data(rom_data),
	.rom_wr(rom_wr),
	.file_active(file_active),
	.file_slot(file_slot),
	.file_addr(file_addr),
	.file_data(file_data),
	.file_wr(file_wr),
	.rks_start(rks_start),
	.rks_ok(rks_ok),
	.aux_req(aux_req),
	.aux_addr(aux_addr),
	.aux_din(aux_din),
	.aux_ack(aux_ack)
);

wire vid_req, vid_valid;
wire [20:0] vid_addr;
wire [15:0] vid_dout;

spec_sram sram (
	.clk(clk),
	.addr(sram_addr),
	.we(sram_we),
	.din(cpu_do),
	.din_hi(cur_color),
	.wr16(sram_wr16),
	.dout(sram_do),
	.rd_ok(),
	.aux_req(aux_req),
	.aux_we(1'b1),
	.aux_addr(aux_addr),
	.aux_din(aux_din),
	.aux_ack(aux_ack),
	.aux_dout(),
	.vid_req(vid_req),
	.vid_addr(vid_addr),
	.vid_dout(vid_dout),
	.vid_valid(vid_valid),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N)
);

spec_video video (
	.clk(clk),
	.mx(mx),
	.cmode(cmode),
	.vid_req(vid_req),
	.vid_addr(vid_addr),
	.vid_dout(vid_dout),
	.vid_valid(vid_valid),
	.rgb(rgb),
	.hs(hs),
	.vs(vs),
	.de(de)
);

endmodule
