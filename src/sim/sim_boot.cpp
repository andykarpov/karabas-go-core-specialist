// sim_boot: tb_boot (spec_system + SRAM model) under verilator (the sim_boot of core-orion128).
//
//   sim_boot --rom FILE:ADDR ... [--mx] [--turbo] [--cmode N] [--noauto] [--ms N]
//            [--file MS:SLOT:FILE ...] [--key MS:B,B,.. ...] [--ppm OUT] [--frame OUT]
//            [--expect ADDR:VAL ...] [--disk FILE] [--save-disk OUT]
//
// The ROMs go in through the ROM loader (one byte every 12 clocks), then the machine runs N ms of its
// time. --file loads a file through the FL port at that time (as the mcu: one byte every 12 clocks,
// the machine is in reset meanwhile). --key sends PS/2 set 2 bytes (hex) at that time, 50 us apart.
// --ppm writes the screen from the SRAM (9000-BFFF, 384 x 256, the colour of each byte from lane 1
// with the palettes of Emu80). --frame captures the next whole frame of the video output (800 x 600).
// Prints a checksum of the screen and how many points are lit. --expect checks a byte of the SRAM
// (a byte address of spec_sram) at the end. --disk: the image of disk A (F slot 4) on a model of the
// file mounter of the firmware, mounted at the start; --save-disk writes it back at the end.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include "Vtb_boot.h"
#include "verilated.h"

static Vtb_boot *top;
static uint64_t clks = 0;

static void mcu_clk();
static bool has_disk = false;

static void tick() {
	top->clk = 0; top->eval();
	if (has_disk) mcu_clk();
	top->clk = 1; top->eval();
	clks++;
}

// ---- the file mounter of the firmware (docs/protocol.md section 6), as core-msx sim_sys: a read is
// answered with 512 bytes (one per 11 clk), the sum, the result; a write is taken with its bytes.
static std::vector<uint8_t> disks[8];       // by slot: 4 --disk
#define disk disks[mcu_slot]
static int mcu_slot = 4;
static uint32_t mcu_lba = 0;
static int mcu_op = 0, mcu_pos = -1, mcu_gap = 0, mcu_wcnt = 0, mcu_bank = 0, mcu_wsum_parts = 0;
static int64_t mcu_wait = -1;
static uint8_t mcu_wbuf[512];
static uint16_t mcu_wsum = 0;
static int mount_wait = 2000, mount_sd = 0;
static int disk_reads = 0, disk_writes = 0;

static void mcu_clk() {
	top->img_q_ack = 0;
	top->img_data_wr = 0;
	top->img_result_wr = 0;
	top->img_mounted = 0;
	if (mount_wait > 0 && --mount_wait == 0) {
		top->img_size = disks[4].size();
		top->img_mounted = 1 << 4;
		mount_sd = 2000;
	}
	if (mount_sd > 0 && --mount_sd == 0 && !disks[6].empty()) {
		top->img_size = disks[6].size();
		top->img_mounted = 1 << 6;
	}
	if (top->img_q_wr && !top->img_q_ack) {
		uint32_t w = top->img_q_di;
		uint8_t c = w >> 16, a = w >> 8, d = w;
		top->img_q_ack = 1;
		if (c == 0x42) {
			if (a == 0) mcu_lba = 0;
			mcu_lba |= (uint32_t)d << (8 * a);
		}
		else if (c == 0x43) {
			mcu_op = d;
			mcu_slot = a;
			mcu_wcnt = 0; mcu_wsum_parts = 0; mcu_wsum = 0;
			if (d == 1) { mcu_wait = 4000; disk_reads++; }
		}
		else if (c == 0x44 && mcu_op == 2) {
			if (a == 0) mcu_bank = d & 1;
			else if (a == 0x10) { mcu_wsum = (mcu_wsum & 0xFF00) | d; mcu_wsum_parts++; }
			else if (a == 0x11) {
				mcu_wsum = (mcu_wsum & 0x00FF) | (d << 8); mcu_wsum_parts++;
				if (mcu_wsum_parts == 2) {
					if (mcu_lba * 512 + 512 <= disk.size()) memcpy(&disk[mcu_lba * 512], mcu_wbuf, 512);
					disk_writes++;
					mcu_op = 0;
					mcu_wait = 4000;
				}
			}
		}
		else if (c == 0x45 && mcu_op == 2) {
			mcu_wbuf[mcu_bank * 256 + a] = d;
			mcu_wcnt++;
		}
	}
	if (mcu_wait > 0) mcu_wait--;
	else if (mcu_wait == 0) {
		mcu_wait = -1;
		if (mcu_op == 1) { mcu_pos = 0; mcu_gap = 0; }
		else { top->img_result = 1; top->img_result_wr = 1; }
	}
	if (mcu_pos >= 0 && ++mcu_gap == 11) {
		mcu_gap = 0;
		if (mcu_pos < 512) {
			size_t o = mcu_lba * 512ull + mcu_pos;
			uint8_t b = o < disk.size() ? disk[o] : 0;
			static uint16_t sum;
			if (mcu_pos == 0) sum = 0;
			sum += b;
			top->img_data_addr = mcu_pos;
			top->img_data = b;
			top->img_data_wr = 1;
			top->img_sum = sum;
			mcu_pos++;
		}
		else {
			mcu_pos = -1;
			mcu_op = 0;
			top->img_result = 1;
			top->img_result_wr = 1;
		}
	}
}


static uint8_t peek(uint32_t a) {
	top->dbg_addr = a; top->eval();
	return top->dbg_q;
}

static std::vector<uint8_t> readfile(const char *name) {
	std::vector<uint8_t> d;
	FILE *f = fopen(name, "rb");
	if (!f) { perror(name); exit(2); }
	int c;
	while ((c = fgetc(f)) != EOF) d.push_back(c);
	fclose(f);
	return d;
}

static const uint32_t pal8[8] = {
	0xFFFFFF, 0xFFFF00, 0xFF00FF, 0xFF0000, 0x00FFFF, 0x00FF00, 0x0000FF, 0x000000
};
static const uint32_t pal16[16] = {
	0x000000, 0x0000C0, 0x00C000, 0x00C0C0, 0xC00000, 0xC000C0, 0xC0C000, 0xC0C0C0,
	0x808080, 0x0000FF, 0x00FF00, 0x00FFFF, 0xFF0000, 0xFF00FF, 0xFFFF00, 0xFFFFFF
};

struct Ev { uint64_t at; int kind; int slot; std::string file; std::vector<uint8_t> keys; };

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	top = new Vtb_boot;
	std::vector<std::pair<std::string, uint32_t>> roms;
	std::vector<std::pair<uint32_t, int>> expects;
	std::vector<Ev> evs;
	int ms = 1000;
	const char *ppm = nullptr, *frame = nullptr, *save_disk = nullptr;
	bool mx = false, turbo = false, autorun = true, z80 = false, ay = false;
	int model = 0, ext = 0, kbd = 0;
	int cmode = 0;
	for (int i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--rom") || !strcmp(argv[i], "--expect")) {
			bool rom = argv[i][2] == 'r';
			std::string s = argv[++i];
			size_t c = s.rfind(':');
			if (rom)
				roms.push_back({ s.substr(0, c), (uint32_t)strtoul(s.c_str() + c + 1, nullptr, 0) });
			else
				expects.push_back({ (uint32_t)strtoul(s.c_str(), nullptr, 0), (int)strtol(s.c_str() + c + 1, nullptr, 0) });
		}
		else if (!strcmp(argv[i], "--file")) {
			std::string s = argv[++i];
			size_t c1 = s.find(':'), c2 = s.find(':', c1 + 1);
			evs.push_back({ strtoull(s.c_str(), nullptr, 0) * 40000, 0, atoi(s.c_str() + c1 + 1), s.substr(c2 + 1), {} });
		}
		else if (!strcmp(argv[i], "--key")) {
			std::string s = argv[++i];
			Ev e { strtoull(s.c_str(), nullptr, 0) * 40000, 1, 0, "", {} };
			const char *p = strchr(s.c_str(), ':') + 1;
			while (*p) { e.keys.push_back(strtoul(p, (char **)&p, 16)); if (*p == ',') p++; }
			evs.push_back(e);
		}
		else if (!strcmp(argv[i], "--disk")) {
			FILE *f = fopen(argv[++i], "rb");
			if (!f) { perror(argv[i]); return 2; }
			int c;
			while ((c = fgetc(f)) != EOF) disks[4].push_back(c);
			fclose(f);
			has_disk = true;
		}
		else if (!strcmp(argv[i], "--save-disk")) save_disk = argv[++i];
		else if (!strcmp(argv[i], "--mx")) { mx = true; model = 1; }
		else if (!strcmp(argv[i], "--mx2")) { mx = true; model = 2; }
		else if (!strcmp(argv[i], "--z80")) z80 = true;
		else if (!strcmp(argv[i], "--ay")) ay = true;
		else if (!strcmp(argv[i], "--ext")) ext = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--kbd")) kbd = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--sd")) {
			FILE *f = fopen(argv[++i], "rb");
			if (!f) { perror(argv[i]); return 2; }
			int c;
			while ((c = fgetc(f)) != EOF) disks[6].push_back(c);
			fclose(f);
			has_disk = true;
		}
		else if (!strcmp(argv[i], "--turbo")) turbo = true;
		else if (!strcmp(argv[i], "--noauto")) autorun = false;
		else if (!strcmp(argv[i], "--cmode")) cmode = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--ms")) ms = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--ppm")) ppm = argv[++i];
		else if (!strcmp(argv[i], "--frame")) frame = argv[++i];
		else { fprintf(stderr, "bad option %s\n", argv[i]); return 2; }
	}
	top->model = model;
	top->cpu_z80 = z80;
	top->ay_on = ay;
	top->ext_port = ext;
	top->kb_layout = kbd;
	top->turbo = turbo;
	top->cmode = cmode;
	top->autorun = autorun;
	top->reset = 1; top->rom_active = 0; top->rom_wr = 0; top->file_active = 0; top->file_wr = 0;
	top->img_q_ack = 0; top->img_data_wr = 0; top->img_result_wr = 0; top->img_mounted = 0;
	top->kb_scancode = 0; top->kb_scancode_upd = 0; top->joy = 0;
	for (int i = 0; i < 400; i++) tick();
	top->reset = 0; top->rom_active = 1;
	for (auto &r : roms) {
		std::vector<uint8_t> d = readfile(r.first.c_str());
		uint32_t a = r.second;
		for (uint8_t c : d) {
			top->rom_addr = a++; top->rom_data = c; top->rom_wr = 1; tick();
			top->rom_wr = 0;
			for (int i = 0; i < 11; i++) tick();
		}
	}
	for (int i = 0; i < 40; i++) tick();
	top->rom_active = 0;
	uint64_t t0 = clks;
	uint64_t end = t0 + (uint64_t)ms * 40000;
	int edges_n = 0, prev = 0, ay_max = 0;
	size_t next = 0;
	while (clks < end) {
		for (auto &e : evs) {
			if (e.at == UINT64_MAX || clks - t0 < e.at) continue;
			if (e.kind == 0) {
				std::vector<uint8_t> d = readfile(e.file.c_str());
				top->file_slot = e.slot; top->file_active = 1;
				for (int i = 0; i < 40; i++) tick();
				for (size_t k = 0; k < d.size(); k++) {
					top->file_addr = k; top->file_data = d[k]; top->file_wr = 1; tick();
					top->file_wr = 0;
					for (int i = 0; i < 11; i++) tick();
				}
				for (int i = 0; i < 40; i++) tick();
				top->file_active = 0;
			}
			else {
				for (uint8_t k : e.keys) {
					top->kb_scancode = k; top->kb_scancode_upd ^= 1;
					for (int i = 0; i < 2000; i++) tick();
				}
			}
			e.at = UINT64_MAX;
		}
		tick();
		if (top->sound && !prev) edges_n++;
		prev = top->sound;
		if (top->ay_sound > ay_max) ay_max = top->ay_sound;
	}
	(void)next;
	std::vector<uint8_t> scr(48 * 256), col(48 * 256);
	uint32_t sum = 0, lit = 0;
	for (int c = 0; c < 48; c++)
		for (int r = 0; r < 256; r++) {
			uint32_t a = (0x9000 + c * 256 + r) << 1;
			uint8_t b = peek(a);
			scr[r * 48 + c] = b;
			col[r * 48 + c] = peek(a | 1);
			sum = sum * 31 + b;
			lit += __builtin_popcount(b);
		}
	printf("%s %s %s %d ms: sound edges %d ay %d screen sum %08x lit %u\n", mx ? "MX" : "Specialist", z80 ? "Z80" : "8080", turbo ? "4MHz" : "2MHz", ms, edges_n, ay_max, sum, lit);
	if (has_disk) printf("disk: %d sectors read, %d written\n", disk_reads, disk_writes);
	if (save_disk) {
		FILE *f = fopen(save_disk, "wb");
		fwrite(disks[4].data(), 1, disks[4].size(), f);
		fclose(f);
	}
	int err = 0;
	for (auto &e : expects) {
		uint8_t v = peek(e.first);
		if (v != e.second) { printf("expect %06x: %02x, not %02x\n", e.first, v, e.second); err = 1; }
	}
	if (ppm) {
		FILE *f = fopen(ppm, "wb");
		fprintf(f, "P6\n384 256\n255\n");
		for (int y = 0; y < 256; y++)
			for (int x = 0; x < 384; x++) {
				int on = (scr[y * 48 + x / 8] >> (7 - x % 8)) & 1;
				uint8_t c = col[y * 48 + x / 8];
				uint32_t rgb = mx ? (on ? pal16[c >> 4] : pal16[c & 15])
				                  : (on ? pal8[((c & 0xC0) >> 5) | ((c & 0x10) >> 4)] : 0);
				uint8_t p[3] = { (uint8_t)(rgb >> 16), (uint8_t)(rgb >> 8), (uint8_t)rgb };
				fwrite(p, 1, 3, f);
			}
		fclose(f);
	}
	if (frame) {
		// the frame starts after the trailing edge of vsync; a line is the run of de
		while (!top->vs) tick();
		while (top->vs) tick();
		std::vector<uint8_t> img(800 * 600 * 3, 0);
		int y = -1, x = 0, de_d = 0;
		while (y < 600) {
			tick();
			if (top->de && !de_d) { y++; x = 0; }
			if (top->de && y >= 0 && y < 600 && x < 800) {
				uint8_t *p = &img[(y * 800 + x) * 3];
				p[0] = top->rgb >> 16; p[1] = top->rgb >> 8; p[2] = top->rgb;
				x++;
			}
			if (!top->de && de_d && y == 599) break;
			de_d = top->de;
		}
		FILE *f = fopen(frame, "wb");
		fprintf(f, "P6\n800 600\n255\n");
		fwrite(img.data(), 1, img.size(), f);
		fclose(f);
	}
	delete top;
	return err;
}
