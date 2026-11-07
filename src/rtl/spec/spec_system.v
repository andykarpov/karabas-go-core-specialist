`timescale 1ns / 1ps
`default_nettype wire

/*
 spec_system.v

 The Specialist and the Specialist-MX: the processor, the memory maps, the ports and the SRAM, on
 one clock of 40 MHz. docs/HARDWARE.md has the maps. The structure is that of orion_system of
 karabas-go-core-orion128. Phase 0: no video, keyboard or MX devices yet (the 8253, the FDC); their
 ports are here for the next phases.

 SRAM (a byte address of 22 bits, spec_sram; a 64 KB page is {bank, a[15:0], lane}):
   000000  the main RAM: lane 0 the bytes, lane 1 the colour of each byte of the screen
           (9000-BFFF), so the video reads points and colour in one access
   020000  the RAM disk of the MX, disks 0..7 = banks 1..4, both lanes
   200000  the Monitor of the Specialist (up to 12 KB, at C000-EFFF), bytes in a row
   210000  the ROM of the MX (48 KB, at 0000-BFFF in the ROM page), bytes in a row
 The ROMs arrive by the ROM loader of the mcu: rom_addr is that byte address, the machine is in
 reset while rom_active.

 The Specialist starts at 0000: after reset its Monitor answers every read (its first bytes are a
 jump to C003), until the first read at C000-FFFF. The MX starts in its ROM page.

 mx (the model) is taken during reset only.
*/

module spec_system (
	input wire clk,
	input wire reset,
	input wire model_mx,         // 0 the Specialist, 1 the Specialist-MX
	input wire turbo,            // the CPU at 4 MHz

	// the ROM loader of the mcu
	input wire rom_active,
	input wire [21:0] rom_addr,
	input wire [7:0] rom_data,
	input wire rom_wr,

	// the keyboard PPI (F800 / FFE0): the matrix of 12 x 6 is scanned both ways
	output wire [7:0] kb_pa_o,   // columns 0..7
	output wire [7:0] kb_pb_o,   // PB7..2 rows 5..0
	output wire [3:0] kb_pc_o,   // PC3..0 columns 8..11
	output wire kb_pa_in,
	output wire kb_pb_in,
	output wire kb_pcl_in,
	input wire [7:0] kb_pa_i,
	input wire [7:2] kb_pb_i,
	input wire [3:0] kb_pc_i,
	input wire kb_nr_n,          // PB1: the key NR (Shift), 0 = pressed
	input wire tape_in,          // PB0

	output wire beep,            // PC5
	output wire tape_out,        // PC7
	output reg mx = 1'b0,

	// the video port of spec_sram
	input wire vid_req,
	input wire [20:0] vid_addr,
	output wire [15:0] vid_dout,
	output wire vid_valid,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N
);

wire run_reset = reset | rom_active;

always @(posedge clk)
	if (run_reset)
		mx <= model_mx;

wire [15:0] a;
wire [7:0] cpu_do;
reg [7:0] cpu_di;
wire mem_rd, mem_wr;

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
	.inte()
);

reg wr_d = 1'b0;
always @(posedge clk)
	wr_d <= mem_wr;
wire wr_p = mem_wr & ~wr_d;   // one clock at the start of a write

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
wire m_col = m_dev && m_reg == 3'd6;   // FFF8
wire m_pag = m_dev && m_reg == 3'd7;   // FFFC

reg [1:0] mpage = 2'd3;      // 0 RAM, 1 RAM disk, 2 / 3 ROM (written by the address FFFC..FFFF)
reg [2:0] mdisk = 3'd0;
reg [7:0] mcolor = 8'h70;    // FFF8: D7..4 points, D3..0 background
always @(posedge clk) begin
	if (run_reset) begin
		mpage <= 2'd3;
		mdisk <= 3'd0;
		mcolor <= 8'h70;
	end
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

// ------------------------------------------------------------------ the PPIs
wire [7:0] kbd_do, usr_do, kb_pc;

spec_ppi ppi_kbd (
	.clk(clk), .reset(run_reset), .a(a[1:0]), .wr(wr_p & sel_kbd), .din(cpu_do), .dout(kbd_do),
	.pa_i(kb_pa_i), .pb_i({ kb_pb_i, kb_nr_n, tape_in }), .pc_i({ 4'hF, kb_pc_i }),
	.pa_in(kb_pa_in), .pb_in(kb_pb_in), .pcl_in(kb_pcl_in),
	.pa_o(kb_pa_o), .pb_o(kb_pb_o), .pc_o(kb_pc)
);
assign kb_pc_o = kb_pc[3:0];
assign beep = kb_pc[5];
assign tape_out = kb_pc[7];

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

always @* begin
	cpu_di = 8'hFF;
	if (sel_kbd) cpu_di = kbd_do;
	else if (sel_usr) cpu_di = usr_do;
	else if (sel_rom || sel_ram || sel_disk) cpu_di = sram_do;
end

// the ROM loader: a byte waits for its slot, the mcu writes one in ten clocks or less often
reg aux_req = 1'b0;
reg [21:0] aux_addr = 22'd0;
reg [7:0] aux_din = 8'd0;
wire aux_ack;
always @(posedge clk) begin
	if (rom_wr) begin
		aux_req <= 1'b1;
		aux_addr <= rom_addr;
		aux_din <= rom_data;
	end
	else if (aux_ack)
		aux_req <= 1'b0;
end

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

endmodule
