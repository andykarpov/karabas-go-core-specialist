# Specialist core for Karabas Go / Mini / Mini G

A core of the Soviet home computers Specialist (1987) and Specialist-MX (1991) for the Karabas Go family of boards (Xilinx Spartan-6 XC6SLX25). Checked on Mini G; built for Go and Mini, not tried on those boards.

What works: KR580VM80A at 2 and 4 MHz; the 384 x 256 screen with the colours of both models; the 12 x 6 keyboard; the beeper, the 8253 of the MX; the memory pages and RAM disk of the MX, RAMFOS; `.rks` programs with autorun; two MX floppy drives (`.odi`), read and write; 800 x 600 and 720 x 576; the tape (not tried).

- [README.ru.md](README.ru.md): this page in Russian.
- [docs/GUIDE.md](docs/GUIDE.md): **how to use it** (Russian): the SD card, keys, OSD.
- [docs/PLAN.md](docs/PLAN.md): research, decisions and phases (Russian).
- [docs/HARDWARE.md](docs/HARDWARE.md): memory maps and ports (Russian).
- [docs/BACKLOG.md](docs/BACKLOG.md): open questions (Russian).

Clone with `--recursive`: the board modules are the submodule `modules/` ([karabas-go-modules](https://github.com/andykarpov/karabas-go-modules)). `src/make_core.py` needs [karabas-go-tools](https://github.com/andykarpov/karabas-go-tools) next to this repository.

License: GPL v3 (`LICENSE`). Third-party code: vm80a (1801BM1, CC-BY 3.0), KF8253 (kitune-san, MIT), wd1793 (V. Slavinsky, Sorgelig, GPL v2 or later, through core-msx and core-orion128). The ROMs of Monitor-2 and RAMFOS come with Emu80. The reference of the behaviour: [Emu80](https://github.com/vpyk/emu80v4) and [Specialist_MiSTer](https://github.com/MiSTer-devel/Specialist_MiSTer).
