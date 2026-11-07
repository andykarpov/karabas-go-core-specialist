# Specialist core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

The Soviet home computers **Specialist** (A. F. Lapin, *Modelist-Konstruktor*, 1987), **Specialist-MX**
(NPO Kometa, 1991) and **Specialist-MX²** for the Karabas Go family of boards (Xilinx Spartan-6
XC6SLX25). One core, three models, chosen in the OSD. All file work (programs, Monitors, ROMs, disk
and SD card images) goes through the OSD and the file browser of the board firmware: the core has no
loader of its own.

| Board | Video | Audio | Floppy connector |
|---|---|---|---|
| Karabas Go | VGA | PCM5102 DAC, beeper | physical drive A / B of the MX |
| Karabas Mini | HDMI with sound | HDMI, sigma-delta output | — |
| Karabas Mini G | HDMI with sound | HDMI, PCM5102 DAC | — |

The core file `specialist.kg` (one file for all three boards) is in `src/` and in the release repo
[karabas-go](https://github.com/andykarpov/karabas-go) (`cores/`).

**State:** build 26110705. Tested on Mini G (see [What is tested](#what-is-tested)). The Go and Mini
builds come from the same sources and meet their timing, but have not been run on those boards yet.

## Contents

- [The three machines](#the-three-machines)
- [What the core does](#what-the-core-does)
- [Getting started](#getting-started)
- [Where to get software](#where-to-get-software)
- [The SD card](#the-sd-card)
- [Ways to use it](#ways-to-use-it)
- [OSD menu](#osd-menu)
- [Keyboard](#keyboard)
- [What is tested](#what-is-tested)
- [Building](#building)
- [Credits and licenses](#credits-and-licenses)

## The three machines

| | Specialist (Original) | Specialist-MX | Specialist-MX² |
|---|---|---|---|
| CPU | KR580VM80A, 2 MHz | KR580VM80A, 2 MHz | KR580VM80A, 2 MHz |
| RAM | 48 KB, the screen included | 64 KB + RAM disk 8 × 64 KB | as the MX |
| ROM | Monitor at C000 (up to 12 KB) | RAMFOS, 48 KB | 64 KB: Monitor-4 and an MX ROM |
| Screen | 384 × 256, colour per byte from the keyboard PPI (8 colours) | 384 × 256, 16 colours per byte (ink / paper from register FFF8) | Specialist colours in its standard mode, MX colours in its MX mode |
| Storage | tape | tape, floppy (KR1818VG93, 800 KB) | as the MX |
| Sound | beeper | 8253 timer | 8253 timer |
| Shell | Monitor | RAMFOS (file manager on the RAM disk) | Monitor-4; RAMFOS on the directive X |

The Specialist has no interrupts and no frame sync: programs never wait for the beam, so the picture
can go out in any standard video mode.

## What the core does

- **Processor:** KR580VM80A (vm80a, a cycle exact model of the chip) or **Z80** (T80), at 2 MHz (as
  the original) or 4 MHz.
- **Video:** the 384 × 256 screen read straight from the SRAM of the board, no frame buffer: 800 × 600
  at 60 Hz (2 × 2 pixels per point) or 720 × 576 at 50 Hz (3:2). The colours of the Specialist (8, 4
  or mono) and the 16 of the MX, with the palettes of Emu80.
- **Keyboard:** the 12 × 6 matrix of the Specialist, scanned both ways as on the machine, with the
  layouts of the original, RAMFOS and Lik. A USB gamepad works as keys.
- **Programs:** `.rks` tape files loaded straight into memory and started by themselves.
- **MX:** the page register (RAM, RAM disk 0..7, ROM), the colour register, the 8253 timer and its
  sound, the floppy controller with two `.odi` drives (read and write, the image cached in the SRAM).
  On the Go the drive connector can be drive A or B.
- **MX²:** its 64 KB ROM, the standard mode with the MX devices at F000, the MX mode.
- **SDOS:** the SD adapter of HWM / PVV at F000 with SDOS, on an SD card image file.
- **AY-3-8910** on the I/O ports 14h / 15h, as in Emu80.
- **Mouse:** the Specialist mouse of Emu80 on the user PPI.
- **Tape:** TAPE_IN and TAPE_OUT of the board for a real tape recorder.

Not there (see `docs/BACKLOG.md`): the SD controller of the MX² and the SD shell of vinxru (a
controller with its own microcontroller), TurboSound, the external ROM disk of MXOS / Commander.

## Getting started

1. Copy `specialist.kg` to the root of the SD card of the board.
2. Make a folder `/specialist` on the card and put programs there (see
   [Where to get software](#where-to-get-software)).
3. Choose **Specialist** in the core menu. The screen shows `PROGRAM ?`.
4. Press **F1**, then **Enter**: the Monitor answers `* МОНИТОР ?`.
5. Open the OSD with **Menu+Esc**, choose **RKS file** (Menu+F2) and pick a `.rks`: it loads and
   starts by itself.

For the MX: set **Model** = MX in the OSD (Menu+M). RAMFOS asks for the date: just press Enter. Its
shell shows the RAM disk, and the function keys are listed at the bottom.

## Where to get software

**Emu80** by Viktor Pykhonin is the best source: the emulator ships with programs, ROMs and images
for the Specialist. Download a release of [vpyk/emu80v4](https://github.com/vpyk/emu80v4/releases)
or browse its `dist/` folder on GitHub:

| Folder of Emu80 | What | Use here |
|---|---|---|
| `dist/spec/sdcard/GAMES` | 127 games (`.rks`) | RKS file |
| `dist/spec/sdcard/SOFT` | 30 programs: BASICs, assemblers, debuggers, Forth, music | RKS file |
| `dist/spec/sd_spec.img` | SD card image with most Specialist software, for SDOS | SD card |
| `dist/spec/sdos_hwmpvv.bin` | the SDOS ROM | SDOS ROM |
| `dist/spec/spec_m1.rom`, `spec_m2.rom`, `spec_m2_qwerty.rom` | Monitor-1, Monitor-2, Monitor-2 for a QWERTY keyboard | Monitor |
| `dist/spec/lik.rom`, `pk01m.rom` | the Lik and PK-01M clones | Monitor |
| `dist/specmx/spmx.rom` | RAMFOS (already built into the core) | MX ROM |
| `dist/specmx/syabr_mx2.bin` | the MX² ROM | MX2 ROM |
| `dist/specmx/sdcard/exolon` | Exolon in four versions: `exolonmx.rks` (MX, 16 colours), `exolon8c.rks`, `exolon4c.rks` (the Specialist in colour), `exolonbw.rks` | RKS file |

Also: [UnivEngineer/Specialist-OS](https://github.com/UnivEngineer/Specialist-OS), an OS for the MX
built from Commander (MXOS) and RAMFOS, with games in `assets/games`.

**Formats:** `.rks` is a tape file: start and end address, the bytes, a checksum (an optional `E6`
and a name in front are understood). `.odi` is a disk of the MX: 80 tracks × 2 sides × 5 sectors of
1024 bytes = 819200 bytes. `.img` is an SD card image (FAT) for SDOS.

## The SD card

```
/specialist.kg
/specialist/
    *.rks                programs (RKS file)
    *.odi                MX disks (Disk A, Disk B)
    sd_spec.img          SD card image for SDOS (SD card)
    sdos_hwmpvv.bin      SDOS ROM (SDOS ROM)
    syabr_mx2.bin        MX² ROM (MX2 ROM)
    lik.rom, ...         other Monitors (Monitor)
```

Monitor-2 and RAMFOS are inside `specialist.kg`. The SDOS and MX² ROMs are not: choose them once in
the OSD, and the firmware loads them at every start of the core. A chosen file is remembered; **Del**
in the OSD forgets it (a ROM item then gives back the built-in ROM at the next start).

## Ways to use it

### The Specialist with its Monitor

After `PROGRAM ?` press F1 and Enter. Useful directives of Monitor-2: `D<start>,<end>` dumps the
memory, `G<address>` runs a program, `R` reads a tape. The memory map and the ports are in
[docs/HARDWARE.md](docs/HARDWARE.md) (Russian).

**Programs:** RKS file (Menu+F2). With **Autorun = On** the Monitor runs for 0.2 s after the load (it
sets up its keyboard port and variables, as after a real start), then the program starts at its
start address. With Autorun = Off the program is only loaded: start it with `G<address>`.

**Other Monitors:** the Monitor item takes any Monitor of up to 12 KB at C000: Monitor-1, Monitor-2
QWERTY, PK-01M, Lik. For the Lik set **Keyboard = Lik** (Esc on the place of F1, no Tab).

**Colour:** the colour Specialist stores 3 bits of colour (PC7, PC6, PC4 of the keyboard PPI) with
every byte written to the screen. **Color** picks how they are shown: 8 colours, 4 colours or mono.
Most programs are black and white; colour versions exist (for example `exolon8c.rks`).

### The Specialist-MX and RAMFOS

Model = MX. RAMFOS starts from the ROM page, asks for the date and shows the RAM disk (up to 8 ×
64 KB). Its function keys: F1 copy, F2 delete, F3 / F4 load / save on tape, F5 editor, F6 boot from
the floppy, F7 debugger. Keyboard = Auto puts the function keys where RAMFOS expects them.

`.rks` files work on the MX too: the file goes into the main RAM (as the MiSTer core loads it), and
with Autorun the machine switches to the RAM page and jumps to it. MX programs in colour with 8253
sound, such as `exolonmx.rks`, run this way.

**Floppy disks:** Disk A (Menu+F7) and Disk B (Menu+F8) take `.odi` images; writes go to the file on
the SD card at once. F6 in RAMFOS boots the disk in drive A: RAMFOS reads track 0 (five sectors to
E400) and runs it if it is a system disk. No image of a real MX system disk was found while the core
was made; one with CP/M, RAMFOS or Bridge Panels should work, and a report is welcome.

**Your own MX ROM:** MX ROM (Menu+F5) replaces RAMFOS with any ROM of up to 48 KB. The MXOS and
Commander ROMs of Emu80 also need an external ROM disk on the PPI, which the core does not have.

**Physical floppy (Go):** in the file browser of Disk A or Disk B the firmware offers the drive on
the connector of the Go instead of an image. It is a KR1818VG93 model with its data separator: 5
sectors of 1024 bytes, 80 tracks, both sides. Not tried on hardware yet.

### The Specialist-MX²

Model = MX2, MX2 ROM = `syabr_mx2.bin`. It starts with `МОНИТОР-4:` in the standard mode (the map
and colours of the Specialist). Directives: `X` the MX mode and RAMFOS, `B` BASIC, `E` editor, `A`
assembler, `Z` disassembler (the Praktik set), `U` the SD shell (needs the SD controller of the MX²,
not in the core). Keyboard = Auto gives the original layout.

### SDOS on an SD card image

Model = Original, Ext port = **SDOS**, SDOS ROM = `sdos_hwmpvv.bin`, SD card = `sd_spec.img`. In the
Monitor type `GD000`: SDOS prints its version and `A:\>`. `DIR` lists, `CD <name>` changes the
folder, `<name>` runs a program; a long listing waits for a key per page. `sd_spec.img` holds most of
the software of the Specialist in folders (`GAMES`, `SYSTEM`). Any FAT image made for the HWM / PVV
adapter works the same way. SDOS takes F000-F7FF, so the user PPI and the mouse are off then.

### Z80

CPU = Z80 (the machine resets). For the Z80 versions of programs ("Specialist Z80" in Emu80); the
Monitor and SDOS run on it too. I/O of the Z80 reaches the devices only; ports C0h-FFh are mapped to
the memory at {n, n}, as on the 8080.

### AY

AY = On: an AY-3-8910 at 1.75 MHz, register number on port 15h, data on port 14h (read too), as in
Emu80. While it is on, OUT / IN to ports below C0h stop writing the memory at {n, n}: on the real
machine an OUT writes there, and a program may rely on it, so keep AY off for such programs.

### Mouse

Ext port = **Mouse**: a USB mouse on the user PPI (F000 on the Specialist, FFE4 on the MX) with the
protocol of Emu80: a falling edge of PB0 gives the next byte of a packet `7F, 08 | buttons, dx, dy,
dz` on port A. For programs written for it.

### Tape

TAPE_IN of the board goes to PB0 of the keyboard PPI, PC7 goes to TAPE_OUT: the tape routines of the
Monitor and RAMFOS work with a real tape recorder (not tried yet). On the MX the tape output is also
heard in the sound, as in Emu80.

### Video

**Video** = 800 × 600 at 60 Hz (the default; a 768 × 512 picture) or 720 × 576 at 50 Hz (576 × 512,
the frame rate of the original). It can change at any time; the OSD stays in the middle.

## OSD menu

Open the OSD with **Menu+Esc**. File items open the browser in `/specialist`. A change of Model or
CPU resets the machine; the other switches act at once.

| Item | Values | Hotkey | What it does |
|---|---|---|---|
| Disk A, Disk B | `.odi` image, or the physical drive (Go) | Menu+F7, Menu+F8 | the floppy drives of the MX / MX² |
| SD card | `.img` | | the SD card image of SDOS |
| RKS file | `.rks` | Menu+F2 | loads a program into the main RAM (Autorun starts it) |
| Monitor | `.rom`, `.bin` | Menu+F4 | a Monitor of the Specialist at C000 instead of Monitor-2 |
| MX ROM | `.rom`, `.bin` | Menu+F5 | a ROM of the MX instead of RAMFOS |
| SDOS ROM | `.bin` | | the SDOS ROM (needed for Ext port = SDOS) |
| MX2 ROM | `.bin` | | the MX² ROM (needed for Model = MX2) |
| Model | Original, MX, MX2 | Menu+M | the machine |
| CPU | KR580VM80A, Z80 | | the processor |
| CPU speed | 2 MHz, 4 MHz | Menu+S | 2 MHz is the original; the 8253 stays at 2 MHz |
| Keyboard | Auto, Original, RAMFOS, Lik | Menu+K | the layout; Auto = RAMFOS on the MX, Original otherwise |
| Color | 8 colors, 4 colors, Mono | Menu+C | the colours of the Specialist (not the MX) |
| Ext port | None, Mouse, SDOS | | what is on the user port |
| AY | Off, On | | the AY on ports 14h / 15h |
| Autorun | On, Off | Menu+A | start a `.rks` after its load |
| Video | 800x600 60Hz, 720x576 50Hz | | the output mode |
| Reset | | F12 | resets the machine |

Ctrl+Alt+Backspace goes back to the boot menu of the board (the firmware).

## Keyboard

The layout is positional, as the QWERTY mode of Emu80: letters and digits are on their places.

| PC key | Specialist |
|---|---|
| Shift | НР (shift) |
| Enter | ВК |
| Backspace | ЗБ |
| Home | cursor home |
| PgUp | СТР (clear screen) |
| PgDn, End | ПС (line feed) |
| Ctrl | ПВ (repeat, Original) |
| Insert, Caps Lock | РУС/ЛАТ |
| `=` | `:` |
| `'` | `^` |
| `` ` `` | `@` |
| F1–F11 | F1–F11 (F1–F10 on the MX) |
| Esc, Tab | Esc, Tab (on their RAMFOS places on the MX; Lik: Esc on the place of F1, no Tab) |

USB gamepad: the arrows are the cursor keys, A is Space, B and Start are Enter.

## What is tested

| | Mini G | Mini | Go |
|---|---|---|---|
| Monitor, keyboard, `.rks` games, colours | yes | — | — |
| RAMFOS, Exolon MX in 16 colours | yes | — | — |
| MX floppy: boot by F6, read and write (test images) | yes | — | — |
| 720 × 576 | yes | — | — |
| SDOS on `sd_spec.img`, on the 8080 and the Z80 | yes | — | — |
| MX²: Monitor-4, RAMFOS by X | yes | — | — |
| Lik Monitor | yes | — | — |
| Sound (beeper, 8253), AY, mouse | simulation only | — | — |
| A real MX system disk, drive B, formatting | not yet (no image) | — | — |
| Physical floppy | | | not yet |
| Tape | not yet | — | — |

## Building

Clone with `--recursive` (the board modules are the submodule `modules/`,
[karabas-go-modules](https://github.com/andykarpov/karabas-go-modules)) and put
[karabas-go-tools](https://github.com/andykarpov/karabas-go-tools) next to this repository. With
ISE 14.7, `cd src && make` builds all three boards and `specialist.kg`; `make minig` builds one
board. `src/sim/run_boot.sh` runs the simulation (verilator, ghdl); `EMU80=<emu80v4>/dist` adds the
SDOS and MX² checks. [CLAUDE.md](CLAUDE.md) has the details, [docs/PLAN.md](docs/PLAN.md) the
decisions and the history (Russian).

## Credits and licenses

The core is GPL v3 (`LICENSE`). Third-party code: vm80a (1801BM1, CC-BY 3.0), T80 (Daniel Wallner,
Sorgelig; BSD style), jt49 (Jose Tejada, GPL v3), wd1793 (V. Slavinsky, Sorgelig, GPL v2 or later,
through core-msx and core-orion128), KF8253 (kitune-san, MIT), vg93 (FD1793_1818VG93 through
core-profi; the upstream has no license file; used for the physical floppy of the Go only). The ROMs
of Monitor-2 and RAMFOS come with Emu80. The reference of the behaviour:
[Emu80](https://github.com/vpyk/emu80v4) by Viktor Pykhonin and
[Specialist_MiSTer](https://github.com/MiSTer-devel/Specialist_MiSTer) by Sorgelig. The structure of
the core follows [core-orion128](https://github.com/andykarpov/karabas-go-core-orion128).
