#!/bin/sh
# 11b: Minix-FS mit einer leeren Datei "notiz" (Inode 2, Zonen 6+7, size 0).
# writefile ueberschreibt sie -> 2 KB Kapazitaet.
set -e
exec python3 - "$1" <<'PYEOF'
import sys, struct, time
disk = sys.argv[1]
BLOCK = 1024
N_INODES = 16
N_ZONES = 64
FIRST_DATA = 5
MAGIC = 0x137F
img = bytearray(BLOCK * N_ZONES)
struct.pack_into('<HHHHHHIHH', img, BLOCK,
    N_INODES, N_ZONES, 1, 1, FIRST_DATA, 0, 0x10081C00, MAGIC, 1)
img[2*BLOCK] = 0b00000111
img[3*BLOCK] = 0b00000111
for i in range(1, BLOCK):
    img[2*BLOCK+i] = 0xFF
    img[3*BLOCK+i] = 0xFF
INODES = 4 * BLOCK
# Inode 1 = Root (2 Eintraege: . ..  + notiz = 3)
struct.pack_into('<HHIIBB9H', img, INODES + 0*32,
    0o040755, 0, 3*16, int(time.time()), 0, 2, FIRST_DATA, 0,0,0,0,0,0,0,0)
# Inode 2 = notiz, leer, zwei reservierte Zonen 6 und 7
struct.pack_into('<HHIIBB9H', img, INODES + 1*32,
    0o100644, 0, 0, int(time.time()), 0, 1, 6, 7, 0,0,0,0,0,0,0)
ROOT = FIRST_DATA * BLOCK
def de(ino, name):
    return struct.pack('<H14s', ino, name.encode().ljust(14, b'\x00'))
img[ROOT:ROOT+16]    = de(1, '.')
img[ROOT+16:ROOT+32] = de(1, '..')
img[ROOT+32:ROOT+48] = de(2, 'notiz')
with open(disk, 'wb') as f:
    f.write(img)
PYEOF
