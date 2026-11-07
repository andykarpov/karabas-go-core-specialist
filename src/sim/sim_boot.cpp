// sim_boot: tb_boot (spec_system + SRAM model) under verilator (the sim_boot of core-orion128).
//
//   sim_boot --rom FILE:ADDR ... [--mx] [--turbo] [--ms N] [--ppm OUT] [--expect ADDR:VAL ...]
//
// The ROMs go in through the ROM loader (one byte every 12 clocks). The machine then runs N ms of
// its time. --ppm writes the screen (9000-BFFF of the main RAM, 384 x 256) with the colour of each
// byte from lane 1 of the SRAM: the 8 colours of the Specialist or the 16 of the MX, the palettes of
// Emu80 (there is no video in phase 0). Prints a checksum of the screen and how many points are lit.
// --expect checks a byte of the SRAM (a byte address of spec_sram) at the end.
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

static const uint32_t pal8[8] = {
	0xFFFFFF, 0xFFFF00, 0xFF00FF, 0xFF0000, 0x00FFFF, 0x00FF00, 0x0000FF, 0x000000
};
static const uint32_t pal16[16] = {
	0x000000, 0x0000C0, 0x00C000, 0x00C0C0, 0xC00000, 0xC000C0, 0xC0C000, 0xC0C0C0,
	0x808080, 0x0000FF, 0x00FF00, 0x00FFFF, 0xFF0000, 0xFF00FF, 0xFFFF00, 0xFFFFFF
};

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	top = new Vtb_boot;
	std::vector<std::pair<std::string, uint32_t>> roms;
	std::vector<std::pair<uint32_t, int>> expects;
	int ms = 1000;
	const char *ppm = nullptr;
	bool mx = false, turbo = false;
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
		else if (!strcmp(argv[i], "--mx")) mx = true;
		else if (!strcmp(argv[i], "--turbo")) turbo = true;
		else if (!strcmp(argv[i], "--ms")) ms = atoi(argv[++i]);
		else if (!strcmp(argv[i], "--ppm")) ppm = argv[++i];
		else { fprintf(stderr, "bad option %s\n", argv[i]); return 2; }
	}
	top->model_mx = mx;
	top->turbo = turbo;
	top->reset = 1; top->rom_active = 0; top->rom_wr = 0;
	top->kb_pa_i = 0xFF; top->kb_pb_i = 0x3F; top->kb_pc_i = 0xF; top->kb_nr_n = 1;
	for (int i = 0; i < 400; i++) tick();
	top->reset = 0; top->rom_active = 1;
	for (auto &r : roms) {
		FILE *f = fopen(r.first.c_str(), "rb");
		if (!f) { perror(r.first.c_str()); return 2; }
		int c; uint32_t a = r.second;
		while ((c = fgetc(f)) != EOF) {
			top->rom_addr = a++; top->rom_data = c; top->rom_wr = 1; tick();
			top->rom_wr = 0;
			for (int i = 0; i < 11; i++) tick();
		}
		fclose(f);
	}
	for (int i = 0; i < 40; i++) tick();
	top->rom_active = 0;
	uint64_t end = clks + (uint64_t)ms * 40000;
	int beeps = 0, prev = 0;
	while (clks < end) {
		tick();
		if (top->beep && !prev) beeps++;
		prev = top->beep;
	}
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
	printf("%s %s %d ms: beep edges %d screen sum %08x lit %u\n", mx ? "MX" : "Specialist", turbo ? "4MHz" : "2MHz", ms, beeps, sum, lit);
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
	delete top;
	return err;
}
