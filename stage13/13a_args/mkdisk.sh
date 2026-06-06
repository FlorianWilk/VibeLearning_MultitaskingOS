#!/bin/sh
# 13a: Minix-FS mit hello, count, echo als Programme.
# Aufruf: mkdisk.sh disk.img build-dir
set -e
exec python3 - "$1" "$2" <<'PYEOF'
import sys, struct, time
disk, builddir = sys.argv[1], sys.argv[2]
progs = [('hello', builddir + '/hello.bin'),
         ('count', builddir + '/count.bin'),
         ('echo',  builddir + '/echo.bin')]
BLOCK = 1024
N_INODES = 16
N_ZONES = 64
FIRST_DATA = 5
MAGIC = 0x137F
img = bytearray(BLOCK * N_ZONES)
struct.pack_into('<HHHHHHIHH', img, BLOCK,
    N_INODES, N_ZONES, 1, 1, FIRST_DATA, 0, 0x10081C00, MAGIC, 1)
nused = 2 + len(progs)
img[2*BLOCK] = (1 << nused) - 1
img[3*BLOCK] = (1 << nused) - 1
for i in range(1, BLOCK):
    img[2*BLOCK+i] = 0xFF
    img[3*BLOCK+i] = 0xFF
INODES = 4 * BLOCK
nentries = 2 + len(progs)
struct.pack_into('<HHIIBB9H', img, INODES + 0*32,
    0o040755, 0, nentries*16, int(time.time()), 0, 2, FIRST_DATA, 0,0,0,0,0,0,0,0)
ROOT = FIRST_DATA * BLOCK
def de(ino, name):
    return struct.pack('<H14s', ino, name.encode().ljust(14, b'\x00'))
img[ROOT:ROOT+16]    = de(1, '.')
img[ROOT+16:ROOT+32] = de(1, '..')
for i, (name, path) in enumerate(progs):
    ino = 2 + i
    zone = FIRST_DATA + 1 + i
    with open(path, 'rb') as f:
        data = f.read()
    assert len(data) <= BLOCK, f"{name} zu gross"
    struct.pack_into('<HHIIBB9H', img, INODES + (ino-1)*32,
        0o100755, 0, len(data), int(time.time()), 0, 1, zone, 0,0,0,0,0,0,0,0)
    img[ROOT + (2+i)*16 : ROOT + (2+i)*16 + 16] = de(ino, name)
    z = zone * BLOCK
    img[z:z+len(data)] = data
with open(disk, 'wb') as f:
    f.write(img)
PYEOF
