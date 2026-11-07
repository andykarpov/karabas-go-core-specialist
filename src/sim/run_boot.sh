#!/bin/bash
# The machine in simulation. Builds sim_boot (verilator) into src/sim/build, runs it from src/; the
# screens are in build/*.ppm.
#  1. the Specialist, Monitor-2 at 2 MHz: PROGRAM ? on the screen and in the video output.
#  2. the same at 4 MHz: the same screen as at 2 MHz.
#  3. keys (held 100 ms: the Monitor debounces): F1 and Enter at PROGRAM ? lead to the Monitor prompt.
#  4. a .rks (mkrks.py: fills columns of the screen in colour, writes 5A at 1000) loads through the FL
#     port and starts by itself 200 ms later; with --noauto it loads but does not start.
#  5. the Specialist-MX, RAMFOS: its date prompt.
#  6. the MX ports (mkrom_mx.py): RAM disk pages, the main RAM, the colour register with a write to the
#     screen, the 8253 channel 0 sounds (100 counts at 2 MHz: 10 kHz, some 5000 edges in 500 ms).
#  7. a .rks on the MX: RAMFOS runs, then the file starts in the RAM page.
#  8. the floppy of the MX (mkrom_fdd.py): Restore, Seek, a sector of side 1 read through the sync port
#     FFF0, the same bytes written to another sector; the memory and the saved image are compared.
#  9. RAMFOS boots a disk on F6 (mkboot_odi.py).
set -eu
H=$(cd "$(dirname "$0")" && pwd)
S=$(cd "$H/.." && pwd)
B=$H/build
mkdir -p "$B"
R=$S/rtl
SRC="$H/tb_boot.v $R/spec/spec_system.v $R/spec/spec_cpu.v $R/spec/spec_ppi.v $R/spec/spec_sram.v $R/spec/spec_kbd.v $R/spec/spec_loader.v $R/spec/spec_video.v $R/spec/spec_fdd_cache.v $R/fdd/wd1793.v $S/../modules/rtl/mcu/img_sdc.v $S/../modules/rtl/mem/kg_spram.v $S/../modules/rtl/mem/kg_sdpram.v $R/vm80a/vm80a.v $R/kf8253/KF8253.v $R/kf8253/KF8253_Control_Logic.v $R/kf8253/KF8253_Counter.v"
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
python3 "$H/mkrom_mx.py" "$B/mx_test.rom"
"$SIM" --mx --rom "$B/mx_test.rom:0x210000" --ms 500 \
	--expect 0x42469:0x33 --expect 0x62469:0x55 --expect 0x18200:0x77 --expect 0x12000:0xFF --expect 0x12001:0x5A \
	| tee "$B/mx_test.txt" || err=1
[ "$(sed -n 's/.*sound edges \([0-9]*\).*/\1/p' "$B/mx_test.txt")" -gt 4000 ] || { echo "mx: the 8253 is silent"; err=1; }
"$SIM" --mx --rom $MX --ms $((T + 500)) --file $T:1:"$B/t.rks" --expect 0x2000:0x5A --expect 0x12000:0xFF || err=1
python3 "$H/mkrom_fdd.py" rom "$B/fdd.rom"
python3 "$H/mkrom_fdd.py" disk "$B/fdd.odi"
# track 2, side 1, sector 3 = sector 27 of the image: byte 0 = 27 * 7 = BD, byte 1023 = BD + 3069 + 3 = BD (mod 256)
"$SIM" --mx --rom "$B/fdd.rom:0x210000" --disk "$B/fdd.odi" --ms 1500 --save-disk "$B/fdd_out.odi" \
	--expect 0x18800:0xBD --expect 0x18FFE:0xBD --expect 0x18200:0x00 --expect 0x18202:0x00 --expect 0x18204:0x5A || err=1
cmp -i 20480:27648 -n 1024 "$B/fdd_out.odi" "$B/fdd.odi" || { echo "fdd: the written sector differs"; err=1; }
[ "$(cmp -l "$B/fdd_out.odi" "$B/fdd.odi" | wc -l)" -le 1024 ] || { echo "fdd: more than one sector changed"; err=1; }
python3 "$H/mkboot_odi.py" "$B/boot.odi"
"$SIM" --mx --rom $MX --disk "$B/boot.odi" --ms 4500 --key 800:5A --key 900:F0,5A --key 2000:0B --key 2100:F0,0B \
	--expect 0x18200:0x5A --expect 0x12000:0xF0 --expect 0x12001:0xC1 || err=1
echo "run_boot: $err errors"
exit $err
