#!/usr/bin/env python3
# A test ROM of the MX for run_boot.sh (loaded as the ROM of the MX, it runs from 0000 of the ROM page).
# A routine in the system RAM (FFC0: STAX D, MOV M,B, STA FFFE, RET) selects a page by the address in DE
# (FFFC the RAM, FFFD the RAM disk A), writes B at HL there and returns to the ROM page. Writes:
#   RAM disk 3, 1234: 33      RAM disk 5, 1234: 55      the main RAM C100: 77 (from the ROM page)
#   the colour register FFF8 = 5A, then FF at 9000 of the RAM page (points FF, colour 5A)
# then sets the keyboard PPI (82: PC5 = 0, the gate open) and the 8253 channel 0 to mode 3, 100.
import sys
c = []
def b(*x): c.extend(x)
b(0x31, 0x00, 0xD0)                      # LXI SP,D000
b(0x21, 0xC0, 0xFF)                      # LXI H,FFC0
for x in (0x12, 0x70, 0x32, 0xFE, 0xFF, 0xC9):
    b(0x36, x, 0x23)                     # MVI M,x; INX H
def call(de, a, hl, v):
    b(0x11, de & 0xFF, de >> 8, 0x3E, a, 0x21, hl & 0xFF, hl >> 8, 0x06, v, 0xCD, 0xC0, 0xFF)
call(0xFFFD, 3, 0x1234, 0x33)
call(0xFFFD, 5, 0x1234, 0x55)
b(0x3E, 0x77, 0x32, 0x00, 0xC1)          # MVI A,77; STA C100
b(0x3E, 0x5A, 0x32, 0xF8, 0xFF)          # MVI A,5A; STA FFF8
call(0xFFFC, 0, 0x9000, 0xFF)
b(0x3E, 0x82, 0x32, 0xE3, 0xFF)          # MVI A,82; STA FFE3 (the keyboard PPI: C out, 0)
b(0x3E, 0x36, 0x32, 0xEF, 0xFF)          # MVI A,36; STA FFEF (channel 0, LSB / MSB, mode 3)
b(0x3E, 100, 0x32, 0xEC, 0xFF)           # MVI A,100; STA FFEC
b(0xAF, 0x32, 0xEC, 0xFF)                # XRA A; STA FFEC
here = len(c)
b(0xC3, here & 0xFF, here >> 8)          # JMP $
open(sys.argv[1], 'wb').write(bytes(c))
