#!/usr/bin/env python3
# A test Monitor for run_boot.sh (at C000, it starts through the mirror of the ROM at 0000): the AY on
# the I/O ports 15 (register) and 14 (data): tone A, volume 15, period 64, then a loop. With the AY on,
# the OUT cycles must not write the memory at 1515 / 1414.
import sys
c = [0xC3, 0x03, 0xC0]
for reg, val in ((7, 0x3E), (8, 0x0F), (0, 0x40), (1, 0x00)):
    c += [0x3E, reg, 0xD3, 0x15, 0x3E, val, 0xD3, 0x14]
here = 0xC000 + len(c)
c += [0xC3, here & 0xFF, here >> 8]
open(sys.argv[1], 'wb').write(bytes(c))
