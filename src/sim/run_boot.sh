#!/bin/bash
# Phase 0 check: both models boot their ROMs. Builds sim_boot (verilator) into src/sim/build, runs it
# from src/; the screens are in build/*.ppm.
#  1. the Specialist, Monitor-2 at 2 MHz: its first screen is not empty.
#  2. the same at 4 MHz: the same screen as at 2 MHz, sooner.
#  3. the Specialist-MX, RAMFOS: its menu is not empty.
set -eu
H=$(cd "$(dirname "$0")" && pwd)
S=$(cd "$H/.." && pwd)
B=$H/build
mkdir -p "$B"
R=$S/rtl
SRC="$H/tb_boot.v $R/spec/spec_system.v $R/spec/spec_cpu.v $R/spec/spec_ppi.v $R/spec/spec_sram.v $R/vm80a/vm80a.v"
verilator --language 1364-2005 --cc --exe --build -j 8 -O3 --top-module tb_boot -Mdir "$B/obj" -o sim_boot \
	-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-PINNOTFOUND \
	--x-initial fast -CFLAGS -O2 $SRC "$H/sim_boot.cpp" > "$B/build.log" 2>&1 || { tail -30 "$B/build.log"; exit 1; }
[ -z "${BUILD_ONLY:-}" ] || exit 0
cd "$S"
SIM=$B/obj/sim_boot
M2=roms/spec_m2.rom:0x200000
MX=roms/spmx.rom:0x210000
T=${BOOT_MS:-1500}
err=0
"$SIM" --rom $M2 --ms $T --ppm "$B/m2.ppm" || err=1
"$SIM" --rom $M2 --turbo --ms $T --ppm "$B/m2_turbo.ppm" || err=1
"$SIM" --mx --rom $MX --ms $T --ppm "$B/mx.ppm" || err=1
for f in m2 m2_turbo mx; do
	[ "$(tail -c +16 "$B/$f.ppm" | tr -d '\000' | wc -c)" -gt 0 ] || { echo "$f: empty screen"; err=1; }
done
cmp -s "$B/m2.ppm" "$B/m2_turbo.ppm" || { echo "m2: 2 and 4 MHz differ"; err=1; }
echo "run_boot: $err errors"
exit $err
