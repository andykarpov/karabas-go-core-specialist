#!/usr/bin/env python3
# A bootable .odi of the MX that tests the floppy on the board (see mkboot_odi.py for the boot of RAMFOS): the
# image is the pattern of mkrom_fdd.py; the boot code at E400 reads track 2, side 1, sector 3 into C400 through
# the sync port FFF0, writes it to track 2, side 0, sector 1, and fills 9000-97FF: green if both
# statuses are 0 and the bytes are the pattern, red if not. The written sector in the image then equals
# the sector 27: compare the file on the SD card.
import sys
FFE8, FFEA, FFEB = 0xFFE8, 0xFFEA, 0xFFEB
ORG = 0xE400
c = []
def b(*x): c.extend(x)
def w(v): return (v & 0xFF, v >> 8)
def sta(a): b(0x32, *w(a))
def lda(a): b(0x3A, *w(a))
def mvi(v): b(0x3E, v)
def pc(): return ORG + len(c)
def wait_busy():
    h = pc(); lda(FFE8); b(0xE6, 0x01); b(0xC2, *w(h))
b(0x31, *w(0xD000))                                  # LXI SP
sta(0xFFFC)                                          # the RAM page
b(0xAF); sta(0xFFF3); sta(0xFFF2)
mvi(0x08); sta(FFE8); wait_busy()
mvi(2); sta(FFEB); mvi(0x18); sta(FFE8); wait_busy()
mvi(1); sta(0xFFF2); mvi(3); sta(FFEA)
mvi(0x80); sta(FFE8)
b(0x21, *w(0xC400), 0x01, *w(0x0400))
h = pc(); sta(0xFFF0); lda(FFEB); b(0x77, 0x23, 0x0B, 0x78, 0xB1); b(0xC2, *w(h))
wait_busy(); lda(FFE8); b(0x47)                      # MOV B,A: the status of the read
b(0xAF); sta(0xFFF2); mvi(1); sta(FFEA)
mvi(0xA0); sta(FFE8)
b(0x21, *w(0xC400), 0x01, *w(0x0400))
h = pc(); sta(0xFFF0); b(0x7E); sta(FFEB); b(0x23, 0x0B, 0x78, 0xB1); b(0xC2, *w(h))
wait_busy(); lda(FFE8); b(0xB0)                      # ORA B
b(0x47); lda(0xC400); b(0xFE, 0xBD)                  # MOV B,A; LDA C400; CPI BD
bad = []
b(0xC2, 0, 0); bad.append(len(c) - 2)                # JNZ bad
b(0x78, 0xB7)                                        # MOV A,B; ORA A
b(0xC2, 0, 0); bad.append(len(c) - 2)                # JNZ bad
mvi(0xA1); good_jmp = len(c)                         # the colour: points green
b(0xC3, 0, 0)
badat = pc()
for x in bad: c[x], c[x + 1] = w(badat)
mvi(0xC1)                                            # points red
fill = pc()
c[good_jmp + 1], c[good_jmp + 2] = w(fill)
sta(0xFFF8)
b(0x21, *w(0x9000))
h = pc(); b(0x36, 0xFF, 0x23, 0x7C, 0xFE, 0x98); b(0xC2, *w(h))
h = pc(); b(0xC3, *w(h))
d = bytearray(800 * 1024)
for s in range(800):
    for i in range(1024):
        d[s * 1024 + i] = (s * 7 + i * 3 + (i >> 8)) & 0xFF
d[:len(c)] = bytes(c)
d[5118] = 0x10
d[5119] = 0x11
open(sys.argv[1], 'wb').write(d)
