`timescale 1ns / 1ps
`default_nettype wire

/*
 Specialist core for Karabas Go (VGA, PCM5102, the beeper). The board glue of core-orion128. The
 floppy connector is the physical drive A or B of the MX (spec_fdd_phys, the browser of Disk A / B).

 The machine is spec_system; all file work goes through the firmware: the ROMs of core.json by the
 ROM loader, .rks files, Monitors and the ROM of the MX by the FL items, disk images by the F items.

 Clocks: one PLL, VCO 800 MHz (50 * 16): clk_sys 40.0 MHz (/20: the machine and 800 x 600 output),
 clk_8 8.0 MHz (/100), a second PLL for the 27.0 MHz of 720 x 576; clk_pix is 40 or 27 MHz through
 a BUFGMUX, by Video in the OSD.

 Soft switches (the index of the item in the osd of core.json, file items included):
   0 Disk A (F 4)   1 Disk B (F 5)   2 SD card (F 6)   3 RKS file (FL 1)   4 Monitor (FL 2)
   5 MX ROM (FL 3)   6 SDOS ROM (FL 7)   7 MX2 ROM (FL 0)   8 -   9 Model (Original / MX / MX2)
   10 CPU (KR580VM80A / Z80)   11 CPU speed (2 / 4 MHz)   12 Keyboard (Auto / Original / RAMFOS / Lik)
   13 Color (8 colors / 4 colors / mono)   14 Ext port (None / Mouse / SDOS)   15 AY (off / on)
   16 Autorun (on / off)   17 Video (800 x 600 60 Hz / 720 x 576 50 Hz)   18 Reset
 A change of the model or the processor resets the machine (they are taken in reset).
*/

module karabas_go_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,
	inout wire ESP_RESET_N,
	inout wire ESP_BOOT_N,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N,
	output wire [1:0] MRD_N,

	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

	output wire SD_CS_N,
	output wire SD_CLK,
	output wire SD_DI,
	input wire SD_DO,
	input wire SD_DET_N,

	output wire [7:0] VGA_R,
	output wire [7:0] VGA_G,
	output wire [7:0] VGA_B,
	output wire VGA_HS,
	output wire VGA_VS,
	output wire V_CLK,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	output wire FT_OE_N,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	input wire FDC_INDEX,
	output wire [1:0] FDC_DRIVE,
	output wire FDC_MOTOR,
	output wire FDC_DIR,
	output wire FDC_STEP,
	output wire FDC_WDATA,
	output wire FDC_WGATE,
	input wire FDC_TR00,
	input wire FDC_WPRT,
	input wire FDC_RDATA,
	output wire FDC_SIDE_N,

	output wire TAPE_OUT,
	input wire TAPE_IN,
	output wire BEEPER,

	output wire DAC_LRCK,
	output wire DAC_DAT,
	output wire DAC_BCK,
	output wire DAC_MUTE,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	input wire MCU_SPI_FT_CS_N,
	input wire MCU_SPI_SD2_CS_N,
	inout wire [1:0] MCU_SPI_IO, // [0] INT of link v2 (firmware IO1, GPIO2), [1] unused (IO0, GPIO14)

	output wire MIDI_TX,
	output wire MIDI_CLK,
	output wire MIDI_RESET_N,

	output wire FLASH_CS_N,
	input wire FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N
);

// ------------------------------------------------------------------ unused

assign SDR_BA = 2'b11;
assign SDR_A = 13'h1FFF;
assign SDR_CLK = 1'b1;
assign SDR_DQM = 2'b11;
assign SDR_WE_N = 1'b1;
assign SDR_CAS_N = 1'b1;
assign SDR_RAS_N = 1'b1;
assign SDR_DQ = 16'bz;

assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;
assign WD = 16'bz;

assign ESP_RESET_N = 1'bz;
assign ESP_BOOT_N = 1'bz;
assign MIDI_TX = 1'b1;
assign MIDI_CLK = 1'b1;
assign MIDI_RESET_N = 1'b1;
assign FT_OE_N = 1'b1;     // the FT812 does not drive the video DAC
assign UART_RX = 1'bz;
assign UART_TX = 1'bz;
assign UART_CTS = 1'bz;

// the floppy connector: spec_fdd_phys (its outputs 0 while no drive is on it)

assign FLASH_CS_N = 1'b1;
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

assign MRD_N = 2'b00;  // SRAM /OE: always on, spec_sram drives MD only with /WE

// ------------------------------------------------------------------ clocks

wire clk_sys, clk_8;
wire locked, areset;

wire [5:0] pll_clk;
kg_pll #(
	.CLKIN_PERIOD(20.0),
	.DIVCLK_DIVIDE(1),
	.CLKFBOUT_MULT(16),
	.CLKOUT0_DIVIDE(20),
	.CLKOUT1_DIVIDE(100),
	.CLKOUT2_DIVIDE(20),
	.BUFG_MASK(6'b000011)  // clk_out[2] raw: the BUFGMUX of the pixel clock
) pll (
	.clk_in(CLK_50MHZ),
	.rst(1'b0),
	.clk_out(pll_clk),
	.locked(locked)
);
assign clk_sys = pll_clk[0];
assign clk_8 = pll_clk[1];
assign areset = ~locked;

// the pixel clock: clk_sys for 800 x 600 at 60 Hz, 27.0 MHz for 720 x 576 at
// 50 Hz (Video in the OSD), of a second PLL on clk_sys (40 * 27 / 2 / 20: less jitter than a DCM for the
// HDMI serialiser after it). BUFGMUX takes the raw outputs: the third output of the first PLL (40 MHz,
// the twin of clk_sys) and that of pll27.
wire clk40_raw = pll_clk[2];
wire clk27_raw, locked27;
wire [5:0] pll27_clk;
kg_pll #(
	.CLKIN_PERIOD(25.0),
	.DIVCLK_DIVIDE(2),
	.CLKFBOUT_MULT(27),     // VCO 540 MHz
	.CLKOUT0_DIVIDE(20),    // 27.0 MHz
	.BUFG_MASK(6'b000000),  // raw: the BUFGMUX of the pixel clock
	.IBUFG(0)
) pll27 (
	.clk_in(clk_sys),
	.rst(areset),
	.clk_out(pll27_clk),
	.locked(locked27)
);
assign clk27_raw = pll27_clk[0];
wire pal;                     // 720 x 576 at 50 Hz (sw_video, from the soft switches)
wire clk_pix;
BUFGMUX pixmux (.I0(clk40_raw), .I1(clk27_raw), .S(pal), .O(clk_pix));

// a change of the video mode: the pixel clock changes, the clocks after it restart
reg pal_d = 1'b0;
reg [7:0] vrst = 8'hFF;
always @(posedge clk_sys) begin
	pal_d <= pal;
	if (pal != pal_d || areset || (pal && !locked27))
		vrst <= 8'hFF;
	else if (vrst != 8'd0)
		vrst <= vrst - 8'd1;
end
wire video_reset = vrst != 8'd0;

// the pixel clock of the video DAC
ODDR2 oddr_v_clk (.Q(V_CLK), .C0(clk_pix), .C1(~clk_pix), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU


wire mcu_sck = MCU_SCK;  // not on a clock pin on the Go

// karabas: MCU link v2 (karabas-go-firmware docs/link_v2.md, kg_mcu2); INT on MCU_SPI_IO[0] (N9, IO1 of the firmware)
wire mcu_int;
assign MCU_SPI_IO[0] = mcu_int;
assign MCU_SPI_IO[1] = 1'bz;

wire [7:0] kb_scancode;
wire [15:0] joy_l16, joy_r16;
wire [12:0] joy_l = joy_l16[12:0], joy_r = joy_r16[12:0];
wire [7:0] ms_x, ms_y, ms_z8, ms_b8;
wire [3:0] ms_z = ms_z8[3:0];
wire [2:0] ms_b = ms_b8[2:0];
wire ms_wr;
wire [1:0] ld_kind;
wire [7:0] ld_slot, ld_data;
wire [31:0] ld_addr;
wire ld_active, ld_wr;
wire [19*8-1:0] sw;
wire mcu_busy;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on, sd2_cs_n, sd2_mosi;
wire img_phys_wr;
wire [15:0] img_phys;
wire [7:0] img_wp;
wire [7:0] ps2_code;
wire ps2_kind, ps2_wr;
wire osd_wr, osd_en, osd_zoom;
wire [11:0] osd_waddr;
wire [7:0] osd_wdata;
wire [23:0] osd_fg, osd_bg;
wire [1:0] osd_alpha, osd_place;
wire [4:0] osd_px, osd_ph;
wire [3:0] osd_py;
wire [5:0] osd_pw;
// the disks: the mounter of kg_mcu2 (the sector interface of img_sdc) to spec_system
wire [7:0] sdc_img_mounted, sdc_rd, sdc_wr, sdc_byte_in_data, sdc_byte_out_data;
wire [63:0] sdc_img_size;
wire [31:0] sdc_sector;
wire sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe;
wire [2:0] sdc_slot;
wire [8:0] sdc_byte_addr;

kg_mcu2 #(
	.CAPS(16'h0004),     // write protected images
	.SW_N(19),
	.CS_FILTER(3),
	.ENABLE_OSD(1),
	.ENABLE_IMG(1),      // the disks: the images of the F items
	.IMG_OUT_LATENCY(3),
	.ENABLE_FT(1),
	.ENABLE_SD2(1)
) mcu (
	.CLK(clk_sys),
	.N_RESET(~areset),

	.MCU_SCK(mcu_sck),
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SS(MCU_CS_N),
	.MCU_INT(mcu_int),
	.MCU_SPI_FT_SS(MCU_SPI_FT_CS_N),
	.MCU_SPI_SD2_SS(MCU_SPI_SD2_CS_N),

	.SW(sw), .SW_WR(), .SW_INDEX(), .SW_VALUE(), .HW_ID(), .DVI_ONLY(dvi_only), .CORE_BUILD(), .FW_BUILD(),
	.BUSY(mcu_busy), .BTNS(), .RELOAD_REQ(1'b0), .RELOAD_CORE(8'd0),

	.KBD(), .KBD_WR(), .PS2_CODE(ps2_code), .PS2_KIND(ps2_kind), .PS2_WR(ps2_wr),
	.MS_X(ms_x), .MS_Y(ms_y), .MS_Z(ms_z8), .MS_B(ms_b8), .MS_WR(ms_wr),
	.JOY_L(joy_l16), .JOY_R(joy_r16), .JOY_WR(),
	.PS2_CMD(16'h0000), .PS2_CMD_WR(1'b0),

	.LD_KIND(ld_kind), .LD_SLOT(ld_slot), .LD_SIZE(), .LD_START(), .LD_ACTIVE(ld_active), .LD_END(),
	.LD_ADDR(ld_addr), .LD_DATA(ld_data), .LD_WR(ld_wr), .LD_READY(1'b1),

	.OSD_WR(osd_wr), .OSD_WADDR(osd_waddr), .OSD_WDATA(osd_wdata), .OSD_EN(osd_en),
	.OSD_FG(osd_fg), .OSD_BG(osd_bg), .OSD_ALPHA(osd_alpha), .OSD_PX(osd_px), .OSD_PY(osd_py),
	.OSD_PW(osd_pw), .OSD_PH(osd_ph), .OSD_PLACE(osd_place), .OSD_ZOOM(osd_zoom),

	.SDC_IMG_MOUNTED(sdc_img_mounted), .SDC_IMG_SIZE(sdc_img_size),
	.SDC_RD(sdc_rd), .SDC_WR(sdc_wr), .SDC_SECTOR(sdc_sector),
	.SDC_BUSY(sdc_busy), .SDC_DONE(sdc_done), .SDC_ERROR(sdc_error), .SDC_SLOT(sdc_slot),
	.SDC_BYTE_IN_STROBE(sdc_byte_in_strobe), .SDC_BYTE_ADDR(sdc_byte_addr),
	.SDC_BYTE_IN_DATA(sdc_byte_in_data), .SDC_BYTE_OUT_DATA(sdc_byte_out_data),
	.IMG_WP(img_wp), .IMG_PHYS_WR(img_phys_wr), .IMG_PHYS(img_phys), .IMG_FLUSH(), .FDD_CHNG_WR(), .FDD_CHNG(),
	.FDD_CHNG_REQ(1'b0), .FDD_CHNG_DS(2'd0), .IMG_ACTIVE(),

	.PORT_OUT_DATA(), .PORT_OUT_WR(), .PORT_OUT_READY(4'b1111), .PORT_IN_DATA(32'd0), .PORT_IN_WR(4'd0),
	.PORT_CFG(128'd0), .PORT_IN_FULL(), .PORT_STAT(), .PORT_STAT_WR(),
	.RTC_A(8'd0), .RTC_DI(8'd0), .RTC_CS(1'b0), .RTC_WR_N(1'b1), .MATRIX_CMD(24'd0), .MATRIX_CMD_WR(1'b0),
	.DEBUG_ADDR(16'd0), .DEBUG_DATA(16'd0), .RTC_DO(),

	.FT_SPI_ON(ft_spi_on), .FT_VGA_ON(), .FT_RESET(), .FT_SCK(), .FT_MOSI(ft_mosi), .FT_MISO(FT_SPI_MISO),
	.FT_CS_N(ft_cs_n),
	.SD2_SCK(), .SD2_MOSI(sd2_mosi), .SD2_MISO(SD_DO), .SD2_CS_N(sd2_cs_n)
);

// the loads of link v2 on the loader signals of spec_system: the roms of the core file (LD kind 0),
// the FL items (kind 2)
wire rom_active = ld_active && ld_kind == 2'd0;
wire rom_wr = ld_wr && ld_kind == 2'd0;
wire [31:0] rom_addr = ld_addr;
wire [7:0] rom_data = ld_data;
wire file_active = ld_active && ld_kind == 2'd2;
wire file_wr = ld_wr && ld_kind == 2'd2;
wire [7:0] file_slot = ld_slot, file_data = ld_data;
wire [31:0] file_addr = ld_addr;

// the toggles of v1 out of the pulses of v2: the PS/2 scancode (set 2) and the mouse report
// (spec_system takes a change of them)
reg kb_upd_t = 1'b0, ms_upd = 1'b0;
reg [7:0] kb_code_r = 8'd0;
always @(posedge clk_sys) begin
	if (ps2_wr && !ps2_kind) begin
		kb_code_r <= ps2_code;
		kb_upd_t <= ~kb_upd_t;
	end
	if (ms_wr)
		ms_upd <= ~ms_upd;
end
assign kb_scancode = kb_code_r;
wire kb_scancode_upd = kb_upd_t;

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? MCU_SCK : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;
assign SD_CS_N = sd2_cs_n;
assign SD_DI = sd2_mosi;
assign SD_CLK = MCU_SCK;

// ------------------------------------------------------------------ soft switches

// the switches: the SW registers of kg_mcu2
wire [1:0] sw_model = sw[9*8 +: 2];
wire sw_z80 = sw[10*8];
wire sw_turbo = sw[11*8];
wire [1:0] sw_kbd = sw[12*8 +: 2];
wire [1:0] sw_cmode = sw[13*8 +: 2];
wire [1:0] sw_ext = sw[14*8 +: 2];
wire sw_ay = sw[15*8];
wire sw_noauto = sw[16*8];
assign pal = sw[17*8];
wire sw_reset = sw[18*8];

// a change of the model or the processor resets the machine
reg [2:0] mx_d = 3'd0;
reg [7:0] mx_rst = 8'd0;
always @(posedge clk_sys) begin
	mx_d <= { sw_z80, sw_model };
	if ({ sw_z80, sw_model } != mx_d)
		mx_rst <= 8'hFF;
	else if (mx_rst != 8'd0)
		mx_rst <= mx_rst - 8'd1;
end

// ------------------------------------------------------------------ the machine

wire [23:0] video_rgb;
wire video_hs, video_vs, video_de;
wire sound, mx;
wire [9:0] ay_sound;

spec_system #(.PHYS_FDD(1), .LINK(2)) spec (
	.clk(clk_sys),
	.reset(areset || sw_reset || mcu_busy || mx_rst != 8'd0),
	.model(sw_model),
	.cpu_z80(sw_z80),
	.turbo(sw_turbo),
	.kb_layout(sw_kbd),
	.ext_port(sw_ext),
	.ay_on(sw_ay),
	.cmode(sw_cmode),
	.autorun(~sw_noauto),
	.rom_active(rom_active),
	.rom_addr(rom_addr[21:0]),
	.rom_data(rom_data),
	.rom_wr(rom_wr),
	.file_active(file_active),
	.file_slot(file_slot),
	.file_addr(file_addr),
	.file_data(file_data),
	.file_wr(file_wr),
	.img_mounted(8'd0),
	.img_size(64'd0),
	.img_wp(img_wp),
	.img_data_wr(1'b0),
	.img_data_addr(9'd0),
	.img_data(8'd0),
	.img_result_wr(1'b0),
	.img_result(8'd0),
	.img_sum(16'd0),
	.img_q_wr(),
	.img_q_di(),
	.img_q_ack(1'b0),
	.sdc_img_mounted_i(sdc_img_mounted), .sdc_img_size_i(sdc_img_size), .sdc_rd_o(sdc_rd), .sdc_wr_o(sdc_wr),
	.sdc_sector_o(sdc_sector), .sdc_busy_i(sdc_busy), .sdc_done_i(sdc_done), .sdc_error_i(sdc_error),
	.sdc_slot_i(sdc_slot), .sdc_byte_in_strobe_i(sdc_byte_in_strobe), .sdc_byte_addr_i(sdc_byte_addr),
	.sdc_byte_in_data_i(sdc_byte_in_data), .sdc_byte_out_data_o(sdc_byte_out_data),
	.kb_scancode(kb_scancode),
	.kb_scancode_upd(kb_scancode_upd),
	.joy(joy_l | joy_r),
	.ms_x(ms_x),
	.ms_y(ms_y),
	.ms_z(ms_z),
	.ms_b(ms_b),
	.ms_upd(ms_upd),
	.clk_pix(clk_pix),
	.pal(pal),
	.rgb(video_rgb),
	.hs(video_hs),
	.vs(video_vs),
	.de(video_de),
	.tape_in(TAPE_IN),
	.tape_out(TAPE_OUT),
	.sound(sound),
	.ay_sound(ay_sound),
	.mx(mx),
	.img_phys_wr(img_phys_wr),
	.img_phys(img_phys),
	.FDC_INDEX(FDC_INDEX), .FDC_DRIVE(FDC_DRIVE), .FDC_MOTOR(FDC_MOTOR), .FDC_DIR(FDC_DIR), .FDC_STEP(FDC_STEP),
	.FDC_WDATA(FDC_WDATA), .FDC_WGATE(FDC_WGATE), .FDC_TR00(FDC_TR00), .FDC_WPRT(FDC_WPRT), .FDC_RDATA(FDC_RDATA),
	.FDC_SIDE_N(FDC_SIDE_N),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N)
);

// ------------------------------------------------------------------ OSD

// the bitmap OSD of link v2 (kg_l2_osd_overlay): written on clk_sys, shown on clk_pix (800 x 600 or
// 720 x 576), centred in de, 2 clocks of latency with its syncs and de
wire [23:0] osd_rgb;
wire osd_hs, osd_vs, osd_de;
kg_l2_osd_overlay osd (
	.wclk(clk_sys),
	.osd_wr(osd_wr), .osd_waddr(osd_waddr), .osd_wdata(osd_wdata), .osd_en(osd_en),
	.osd_fg(osd_fg), .osd_bg(osd_bg), .osd_alpha(osd_alpha), .osd_px(osd_px), .osd_py(osd_py),
	.osd_pw(osd_pw), .osd_ph(osd_ph), .osd_place(osd_place), .osd_zoom(osd_zoom),
	.icon_on(8'd0), .icon_act(8'd0),
	.clk(clk_pix),
	.rgb_i(video_rgb), .hs_i(video_hs), .vs_i(video_vs), .de_i(video_de),
	.rgb_o(osd_rgb), .hs_o(osd_hs), .vs_o(osd_vs), .de_o(osd_de)
);

// ------------------------------------------------------------------ audio

// the MX hears its tape output too (Emu80), quieter
wire [15:0] audio = (sound ? 16'h1800 : 16'h0000) + (mx && TAPE_OUT ? 16'h0600 : 16'h0000) + { 2'b00, ay_sound, 4'b0000 };

kg_pcm5102 #(.DIV_BITS(2)) dac (  // bck 5 MHz, 156 kHz
	.clk(clk_sys),
	.reset(areset),
	.left(audio),
	.right(audio),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_LRCK)
);
assign DAC_MUTE = 1'b1;  // soft mute of the PCM5102: 1 = sound on
assign BEEPER = sound;

// ------------------------------------------------------------------ VGA

// 800 x 600: positive syncs; 720 x 576: negative
assign VGA_R = osd_rgb[23:16];
assign VGA_G = osd_rgb[15:8];
assign VGA_B = osd_rgb[7:0];
// the syncs of the overlay (in step with osd_rgb), negative for 576p as on HDMI
assign VGA_HS = pal ? ~osd_hs : osd_hs;
assign VGA_VS = pal ? ~osd_vs : osd_vs;

endmodule
