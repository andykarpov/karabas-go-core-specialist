#!/usr/bin/env python3
# A test ROM of the floppy of the MX for run_boot.sh, and its disk image.
#   mkrom_fdd.py rom OUT     runs from 0000 of the ROM page: Restore, Seek to track 2, side 1, reads
#     sector 3 into C400-C7FF through the sync port FFF0, writes it to track 2, side 0, sector 1,
#     then the status of the read at C100 and of the write at C101, 5A at C102 at the end.
#   mkrom_fdd.py disk OUT    an 800 KB image: each byte is a function of its sector and offset.
import sys
FFE8, FFEA, FFEB = 0xFFE8, 0xFFEA, 0xFFEB
c = []
def b(*x): c.extend(x)
def w(v): return (v & 0xFF, v >> 8)
def sta(a): b(0x32, *w(a))
def lda(a): b(0x3A, *w(a))
def mvi(v): b(0x3E, v)
def wait_busy():
    here = len(c)
    lda(FFE8); b(0xE6, 0x01); b(0xC2, *w(here))      # LDA; ANI 1; JNZ
b(0x31, 0x00, 0xD0)                                  # LXI SP,D000
b(0x21, 0x00, 0x40)                                  # LXI H,4000: time for the mount
here = len(c); b(0x2B, 0x7C, 0xB5); b(0xC2, *w(here))  # DCX H; MOV A,H; ORA L; JNZ
b(0xAF); sta(0xFFF3); sta(0xFFF2)                    # XRA A: drive 0, side 0
mvi(0x08); sta(FFE8); wait_busy()                    # Restore
mvi(2); sta(FFEB); mvi(0x18); sta(FFE8); wait_busy() # Seek 2
mvi(1); sta(0xFFF2); mvi(3); sta(FFEA)               # side 1, sector 3
mvi(0x80); sta(FFE8)                                 # Read Sector
b(0x21, *w(0xC400), 0x01, *w(0x0400))                # LXI H; LXI B,1024
here = len(c)
sta(0xFFF0); lda(FFEB); b(0x77, 0x23, 0x0B, 0x78, 0xB1); b(0xC2, *w(here))  # sync; data; MOV M,A; INX H; DCX B; MOV A,B; ORA C
wait_busy(); lda(FFE8); sta(0xC100)
b(0xAF); sta(0xFFF2); mvi(1); sta(FFEA)              # side 0, sector 1
mvi(0xA0); sta(FFE8)                                 # Write Sector
b(0x21, *w(0xC400), 0x01, *w(0x0400))
here = len(c)
sta(0xFFF0); b(0x7E); sta(FFEB); b(0x23, 0x0B, 0x78, 0xB1); b(0xC2, *w(here))  # sync; MOV A,M; data; ...
wait_busy(); lda(FFE8); sta(0xC101)
mvi(0x5A); sta(0xC102)
here = len(c); b(0xC3, *w(here))
if sys.argv[1] == 'rom':
    open(sys.argv[2], 'wb').write(bytes(c))
else:
    d = bytearray(800 * 1024)
    for s in range(800):
        for i in range(1024):
            d[s * 1024 + i] = (s * 7 + i * 3 + (i >> 8)) & 0xFF
    open(sys.argv[2], 'wb').write(d)
