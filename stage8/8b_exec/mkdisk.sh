#!/bin/sh
# 8b: Minix-FS-Image mit mehreren Programmen als Dateien.
# Aufruf vom Makefile: mkdisk.sh disk.img build-dir
# Packt build-dir/hello.bin als "hello" und build-dir/count.bin als "count".
set -e
exec python3 - "$1" "$2" <<'PYEOF'
import sys, struct, time

disk, builddir = sys.argv[1], sys.argv[2]
progs = [('hello', builddir + '/hello.bin'),
         ('count', builddir + '/count.bin')]

BLOCK = 1024
N_INODES = 16
N_ZONES = 64
N_IMAP, N_ZMAP = 1, 1
N_INODE_BLOCKS = 1
FIRST_DATA = 2 + N_IMAP + N_ZMAP + N_INODE_BLOCKS    # = 5 (Root-Dir-Zone)
MAGIC = 0x137F

img = bytearray(BLOCK * N_ZONES)

# Superblock (Block 1)
struct.pack_into('<HHHHHHIHH', img, BLOCK,
    N_INODES, N_ZONES, N_IMAP, N_ZMAP, FIRST_DATA, 0, 0x10081C00, MAGIC, 1)

# Bitmaps (Block 2/3): unser Kernel-Reader ignoriert sie, aber fuers Tooling
nused = 2 + len(progs)                  # null + root + progs
bits = (1 << nused) - 1
img[2*BLOCK] = bits
img[3*BLOCK] = bits
for i in range(1, BLOCK):
    img[2*BLOCK + i] = 0xFF
    img[3*BLOCK + i] = 0xFF

INODES = 4 * BLOCK
# Inode 1 = Root-Verzeichnis
nentries = 2 + len(progs)               # . .. + progs
struct.pack_into('<HHIIBB9H', img, INODES + 0*32,
    0o040755, 0, nentries*16, int(time.time()), 0, 2,
    FIRST_DATA, 0,0,0,0,0,0,0,0)

# Programm-Inodes + Daten
ROOT = FIRST_DATA * BLOCK
def de(ino, name):
    return struct.pack('<H14s', ino, name.encode().ljust(14, b'\x00'))
img[ROOT:ROOT+16]    = de(1, '.')
img[ROOT+16:ROOT+32] = de(1, '..')

for i, (name, path) in enumerate(progs):
    inode_nr = 2 + i
    zone = FIRST_DATA + 1 + i           # Daten-Zone (nach Root-Dir)
    with open(path, 'rb') as f:
        data = f.read()
    assert len(data) <= BLOCK, f"{name} zu gross"
    struct.pack_into('<HHIIBB9H', img, INODES + (inode_nr-1)*32,
        0o100755, 0, len(data), int(time.time()), 0, 1,
        zone, 0,0,0,0,0,0,0,0)
    off = ROOT + (2 + i) * 16
    img[off:off+16] = de(inode_nr, name)
    z = zone * BLOCK
    img[z:z+len(data)] = data

with open(disk, 'wb') as f:
    f.write(img)
PYEOF
