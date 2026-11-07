# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A new core of the Soviet home computers Specialist (KR580VM80A, 2 MHz, 384 x 256, 1987) and Specialist-MX (RAMFOS, RAM disk, floppy, 16 colours, 8253 timer, 1991) for the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25, ISE 14.7 (XST).

Status: plan and build skeleton, no RTL yet. Docs, in Russian: `docs/PLAN.md` (research, decisions, architecture, phases), `docs/HARDWARE.md` (memory maps and ports), `docs/BACKLOG.md` (open decisions, things to verify). Follow the phases; record a changed decision in PLAN.md.

All file work goes through the firmware (OSD, `FL` / `F` items, burst): no loader or soft CPU in the core. The machine is our own synchronous Verilog. Emu80 v4 (`vpyk/emu80v4`, GPL-3) is the reference of the behaviour; the MiST / MiSTer core of Sorgelig has no license file, so it is a reference, not a source to copy. The core is GPL v3 (`LICENSE`).

The base is `../karabas-go-core-orion128` (the Orion-128 descends from the Specialist): take `orion_cpu`, `orion_sram`, `orion_video` / `orion_video_576`, `orion_ppi`, `orion_loader`, `orion_fdd_cache`, `wd1793`, the tops, the sim harness from it, renamed `spec_*`, with credit. The 8253 is `KF8253` (kitune-san, MIT) of `../karabas-go-core-pcxt`.

## Layout

- `src/Makefile`: the ISE flow, as in orion128. `src/karabas_<board>.{prj,xst,ut,ucf}`: its inputs (copied from orion128; the timing block of the `.ucf` describes the 40 MHz clock plan).
- `src/make_core.py`: a symlink to `../../karabas-go-tools/make_core/make_core.py`. `src/tools/check_osd.py`: the slot check of `make core`.
- `src/core.json`: the core file description (kgo2, one file for all boards, `specialist.kg`). Mini G only until Ф4.
- `modules/`: the git submodule [karabas-go-modules](https://github.com/andykarpov/karabas-go-modules), its rules are in `modules/CLAUDE.md`. A change there is made there and taken here by moving the submodule. Clone with `--recursive`.

## Build

- `cd src && make minig` (or `go`, `mini`; no target: all boards), `make minig-xst`, `-impl`, `-core`, `make minig-report`; `make spec-xst` / `spec-report` for the machine alone (Ф0). It sources `/opt/Xilinx/14.7/ISE_DS/settings64.sh`. One build at a time. XST returns 0 on an HDL error: check `ERROR` in the `.syr`.
- A new source file goes into `karabas_<board>.prj`. No coregen: inferred memories and `kg_pll`, `kg_dcm`.
- The `.bin` and `.kg` files of a release are committed, and `build` of `core.json` is the id `YYMMDDNN`.

## Rules of the core

The rules of orion128 apply (its `CLAUDE.md`, "Rules of the core"): one 40 MHz clock with enables, standard video timing with syncs always present, `FT_CLK_OUT` about 8 MHz on Mini / Mini G, Go `FDC_*` outputs 0 when unused, SDRAM idle (Mini G2 `~CS` = FLASH_CS_N, drive 1), OSD switch index = item position unless `"index"`, Verilog-2001 for XST, imported code marked `// karabas:`.

- ROMs are not ours: only those the user allowed go into the repo and the `.kg`, others come from `/specialist` on the SD card through `FL` items.
- Before a step that needs the board or the HDMI capture, tell the user: they may be unplugged. Ask before a firmware flash.
- One branch per phase of `docs/PLAN.md`, one PR at its end.

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`, `link.sh` there makes the links). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
