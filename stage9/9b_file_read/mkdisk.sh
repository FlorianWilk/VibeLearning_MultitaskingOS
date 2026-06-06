#!/bin/sh
# 9b: Minix-FS mit einer Textdatei "greet.txt" zum Lesen.
# Aufruf: mkdisk.sh disk.img [build-dir]
set -e
exec python3 - "$1" <<'PYEOF'
import sys, struct, time

disk = sys.argv[1]
files = [('greet.txt', b'Datei per readfile-Syscall gelesen.\nMinix-FS funktioniert.\n')]

BLOCK = 1024
N_INODES = 16
N_ZONES = 64
N_IMAP, N_ZMAP = 1, 1
N_INODE_BLOCKS = 1
FIRST_DATA = 2 + N_IMAP + N_ZMAP + N_INODE_BLOCKS    # 5
MAGIC = 0x137F

img = bytearray(BLOCK * N_ZONES)
struct.pack_into('<HHHHHHIHH', img, BLOCK,
    N_INODES, N_ZONES, N_IMAP, N_ZMAP, FIRST_DATA, 0, 0x10081C00, MAGIC, 1)

nused = 2 + len(files)
img[2*BLOCK] = (1 << nused) - 1
img[3*BLOCK] = (1 << nused) - 1
for i in range(1, BLOCK):
    img[2*BLOCK+i] = 0xFF
    img[3*BLOCK+i] = 0xFF

INODES = 4 * BLOCK
nentries = 2 + len(files)
struct.pack_into('<HHIIBB9H', img, INODES + 0*32,
    0o040755, 0, nentries*16, int(time.time()), 0, 2, FIRST_DATA, 0,0,0,0,0,0,0,0)

ROOT = FIRST_DATA * BLOCK
def de(ino, name):
    return struct.pack('<H14s', ino, name.encode().ljust(14, b'\x00'))
img[ROOT:ROOT+16]    = de(1, '.')
img[ROOT+16:ROOT+32] = de(1, '..')

for i, (name, data) in enumerate(files):
    ino = 2 + i
    zone = FIRST_DATA + 1 + i
    struct.pack_into('<HHIIBB9H', img, INODES + (ino-1)*32,
        0o100644, 0, len(data), int(time.time()), 0, 1, zone, 0,0,0,0,0,0,0,0)
    img[ROOT + (2+i)*16 : ROOT + (2+i)*16 + 16] = de(ino, name)
    z = zone * BLOCK
    img[z:z+len(data)] = data

with open(disk, 'wb') as f:
    f.write(img)
PYEOF
