#!/usr/bin/env python3
# A test .rks for run_boot.sh: at 4000 it writes 5A at 1000, sets the colour (PC6 of the keyboard
# PPI: colour 2 of the eight), fills 9000-97FF (columns 0..7) with FF and stops in a loop.
import sys
code = bytes([
    0x3E, 0x5A, 0x32, 0x00, 0x10,        # MVI A,5A; STA 1000
    0x3E, 0x40, 0x32, 0x02, 0xFF,        # MVI A,40; STA FF02 (port C)
    0x21, 0x00, 0x90,                    # LXI H,9000
    0x36, 0xFF, 0x23, 0x7C, 0xFE, 0x98,  # loop: MVI M,FF; INX H; MOV A,H; CPI 98
    0xC2, 0x0D, 0x40,                    # JNZ loop
    0xC3, 0x16, 0x40,                    # JMP $
])
start = 0x4000
end = start + len(code) - 1
cs = sum(code) & 0xFFFF
open(sys.argv[1], 'wb').write(start.to_bytes(2, 'little') + end.to_bytes(2, 'little') + code + cs.to_bytes(2, 'little'))
