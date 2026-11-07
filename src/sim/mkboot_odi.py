#!/usr/bin/env python3
# A bootable .odi of the MX for run_boot.sh and the board. RAMFOS boots on F6 (ROM 0x1074, runtime F854):
# Read Sector with the multiple flag (90) of track 0, side 0, sectors 1..5 into E400-F7FF, status 01,
# [F7FF] = [F7FE] + 1, CALL E400. The code here selects the RAM page, sets the colour A4 (points red, background
# blue-ish by the palette), fills 9000-97FF, writes 5A at C100 and stops. The rest of the image is E5.
import sys
c = bytes([
    0x32, 0xFC, 0xFF,                    # STA FFFC: the RAM page
    0x3E, 0xC1, 0x32, 0xF8, 0xFF,        # MVI A,C1; STA FFF8: points red, background blue
    0x21, 0x00, 0x90,                    # LXI H,9000
    0x36, 0xF0, 0x23, 0x7C, 0xFE, 0x98,  # loop: MVI M,F0; INX H; MOV A,H; CPI 98
    0xC2, 0x0B, 0xE4,                    # JNZ loop
    0x3E, 0x5A, 0x32, 0x00, 0xC1,        # MVI A,5A; STA C100
    0xC3, 0x19, 0xE4,                    # JMP $
])
d = bytearray(b'\xE5' * (800 * 1024))
d[:len(c)] = c
d[5118] = 0x10
d[5119] = 0x11
open(sys.argv[1], 'wb').write(d)
