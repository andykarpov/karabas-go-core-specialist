#!/bin/bash
# The machine in simulation. Builds sim_boot (verilator) into src/sim/build, runs it from src/; the
# screens are in build/*.ppm.
#  1. the Specialist, Monitor-2 at 2 MHz: PROGRAM ? on the screen and in the video output.
#  2. the same at 4 MHz: the same screen as at 2 MHz.
#  3. keys (held 100 ms: the Monitor debounces): F1 and Enter at PROGRAM ? lead to the Monitor prompt.
#  4. a .rks (mkrks.py: fills columns of the screen in colour, writes 5A at 1000) loads through the FL
#     port and starts by itself 200 ms later; with --noauto it loads but does not start.
#  5. the Specialist-MX, RAMFOS: its date prompt.
set -eu
H=$(cd "$(dirname "$0")" && pwd)
S=$(cd "$H/.." && pwd)
B=$H/build
mkdir -p "$B"
R=$S/rtl
SRC="$H/tb_boot.v $R/spec/spec_system.v $R/spec/spec_cpu.v $R/spec/spec_ppi.v $R/spec/spec_sram.v $R/spec/spec_kbd.v $R/spec/spec_loader.v $R/spec/spec_video.v $R/vm80a/vm80a.v"
verilator --language 1364-2005 --cc --exe --build -j 8 -O3 --top-module tb_boot -Mdir "$B/obj" -o sim_boot \
	-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-PINNOTFOUND \
	--x-initial fast -CFLAGS -O2 $SRC "$H/sim_boot.cpp" > "$B/build.log" 2>&1 || { tail -30 "$B/build.log"; exit 1; }
[ -z "${BUILD_ONLY:-}" ] || exit 0
cd "$S"
SIM=$B/obj/sim_boot
M2=roms/spec_m2.rom:0x200000
MX=roms/spmx.rom:0x210000
T=${BOOT_MS:-1000}
err=0
nonempty() { [ "$(tail -c +16 "$B/$1.ppm" | tr -d '\000' | wc -c)" -gt 0 ] || { echo "$1: empty"; err=1; }; }

"$SIM" --rom $M2 --ms $T --ppm "$B/m2.ppm" --frame "$B/m2_frame.ppm" || err=1
"$SIM" --rom $M2 --turbo --ms $T --ppm "$B/m2_turbo.ppm" || err=1
nonempty m2; nonempty m2_frame
cmp -s "$B/m2.ppm" "$B/m2_turbo.ppm" || { echo "m2: 2 and 4 MHz differ"; err=1; }

"$SIM" --rom $M2 --ms $((T + 800)) --key $T:05 --key $((T + 100)):F0,05 --key $((T + 300)):5A --key $((T + 400)):F0,5A \
	--ppm "$B/m2_key.ppm" || err=1
if cmp -s "$B/m2.ppm" "$B/m2_key.ppm"; then echo "the keys changed nothing"; err=1; fi

python3 "$H/mkrks.py" "$B/t.rks"
"$SIM" --rom $M2 --ms $((T + 500)) --file $T:1:"$B/t.rks" --ppm "$B/rks.ppm" --frame "$B/rks_frame.ppm" \
	--expect 0x2000:0x5A --expect 0x12000:0xFF || err=1
"$SIM" --rom $M2 --noauto --ms $((T + 500)) --file $T:1:"$B/t.rks" --expect 0x2000:0x00 || err=1

"$SIM" --mx --rom $MX --ms $T --ppm "$B/mx.ppm" --frame "$B/mx_frame.ppm" || err=1
nonempty mx; nonempty mx_frame
echo "run_boot: $err errors"
exit $err
