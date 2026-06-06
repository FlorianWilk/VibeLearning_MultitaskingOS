#!/bin/sh
# 5: Minix-FS-Image wie 3c..3f, aber als einzige Datei /init.bin (der
# User-Programm-Code aus $2). Damit kann der Kernel zur Boot-Zeit
# init.bin im Root finden und laden -- genau wie /sbin/init bei echtem Unix.
#
# Aufruf vom Makefile: mkdisk.sh disk.img user.bin
set -e
exec python3 - "$1" "$2" <<'PYEOF'
import sys, struct, time

BLOCK = 1024
N_INODES = 16
N_ZONES = 64
N_IMAP, N_ZMAP = 1, 1
N_INODE_BLOCKS = 1
FIRST_DATA = 2 + N_IMAP + N_ZMAP + N_INODE_BLOCKS    # = 5
MAGIC = 0x137F

with open(sys.argv[2], 'rb') as f:
    init_data = f.read()

assert len(init_data) <= BLOCK, \
    f"init.bin zu gross ({len(init_data)} B), brauche Multi-Zone-Support"

img = bytearray(BLOCK * N_ZONES)

# Superblock
struct.pack_into('<HHHHHHIHH', img, BLOCK,
    N_INODES, N_ZONES, N_IMAP, N_ZMAP,
    FIRST_DATA, 0, 0x10081C00, MAGIC, 1)

# Inode-Bitmap: NULL, root, init.bin
img[2*BLOCK] = 0b00000111
for i in range(1, BLOCK):
    img[2*BLOCK + i] = 0xFF

# Zone-Bitmap: NULL, root-dir-data, init-data
img[3*BLOCK] = 0b00000111
for i in range(1, BLOCK):
    img[3*BLOCK + i] = 0xFF

INODES = 4 * BLOCK
# Inode 1 = Root
struct.pack_into('<HHIIBB9H', img, INODES + 0*32,
    0o040755, 0, 3*16, int(time.time()), 0, 2,
    FIRST_DATA, 0,0,0,0,0,0,0,0)
# Inode 2 = init.bin (executable 0755)
struct.pack_into('<HHIIBB9H', img, INODES + 1*32,
    0o100755, 0, len(init_data), int(time.time()), 0, 1,
    FIRST_DATA + 1, 0,0,0,0,0,0,0,0)

def de(ino, name):
    return struct.pack('<H14s', ino, name.encode().ljust(14, b'\x00'))

ROOT = FIRST_DATA * BLOCK
img[ROOT:ROOT+16] = de(1, '.')
img[ROOT+16:ROOT+32] = de(1, '..')
img[ROOT+32:ROOT+48] = de(2, 'init.bin')

INIT_OFF = (FIRST_DATA + 1) * BLOCK
img[INIT_OFF:INIT_OFF + len(init_data)] = init_data

with open(sys.argv[1], 'wb') as f:
    f.write(img)
PYEOF
