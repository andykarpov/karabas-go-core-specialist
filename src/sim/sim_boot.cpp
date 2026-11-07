// sim_boot: tb_boot (spec_system + SRAM model) under verilator (the sim_boot of core-orion128).
//
//   sim_boot --rom FILE:ADDR ... [--mx] [--turbo] [--cmode N] [--noauto] [--ms N]
//            [--file MS:SLOT:FILE ...] [--key MS:B,B,.. ...] [--ppm OUT] [--frame OUT]
//            [--expect ADDR:VAL ...]
//
// The ROMs go in through the ROM loader (one byte every 12 clocks), then the machine runs N ms of its
// time. --file loads a file through the FL port at that time (as the mcu: one byte every 12 clocks,
// the machine is in reset meanwhile). --key sends PS/2 set 2 bytes (hex) at that time, 50 us apart.
// --ppm writes the screen from the SRAM (9000-BFFF, 384 x 256, the colour of each byte from lane 1
// with the palettes of Emu80). --frame captures the next whole frame of the video output (800 x 600).
// Prints a checksum of the screen and how many points are lit. --expect checks a byte of the SRAM
// (a byte address of spec_sram) at the end.
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

static void tick() {
	top->clk = 0; top->eval();
	top->clk = 1; top->eval();
	clks++;
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
	const char *ppm = nullptr, *frame = nullptr;
	bool mx = false, turbo = false, autorun = true;
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
		else if (!strcmp(argv[i], "--mx")) mx = true;
		else if (!strcmp(argv[i], "--turbo")) turbo = true;
		else if (!strcmp(argv[i], "--noauto")) autorun = false;
		else if (!strcmp(argv[i], "--cmode")) cmode = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--ms")) ms = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--ppm")) ppm = argv[++i];
		else if (!strcmp(argv[i], "--frame")) frame = argv[++i];
		else { fprintf(stderr, "bad option %s\n", argv[i]); return 2; }
	}
	top->model_mx = mx;
	top->turbo = turbo;
	top->cmode = cmode;
	top->autorun = autorun;
	top->reset = 1; top->rom_active = 0; top->rom_wr = 0; top->file_active = 0; top->file_wr = 0;
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
	int edges_n = 0, prev = 0;
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
	printf("%s %s %d ms: sound edges %d screen sum %08x lit %u\n", mx ? "MX" : "Specialist", turbo ? "4MHz" : "2MHz", ms, edges_n, sum, lit);
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
