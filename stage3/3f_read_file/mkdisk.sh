#!/bin/sh
# 3c: baut ein gueltiges Minix-v1-Dateisystem-Image. Kein mount/sudo noetig --
# wir schreiben die FS-Strukturen direkt als Bytes. Layout (1024-Byte-Bloecke):
#   Block 0: Bootblock (leer)
#   Block 1: Superblock
#   Block 2: Inode-Bitmap
#   Block 3: Zone-Bitmap
#   Block 4: Inode-Tabelle (16 Inodes a 32 Byte = 512 Byte)
#   Block 5: Root-Verzeichnis (Dir-Eintraege)
#   Block 6: Inhalt von hello.txt
# Die folgenden Bloecke sind ungenutzt.
set -e
exec python3 - "$1" <<'PYEOF'
import sys, struct, time

BLOCK = 1024
N_INODES = 16
N_ZONES = 64                       # gesamte Bloecke im FS (= 64 KB)
N_IMAP, N_ZMAP = 1, 1
N_INODE_BLOCKS = (N_INODES * 32 + BLOCK - 1) // BLOCK   # = 1
FIRST_DATA = 2 + N_IMAP + N_ZMAP + N_INODE_BLOCKS        # = 5

MAGIC_V1_14 = 0x137F               # Minix v1, 14-Zeichen-Namen

HELLO = b'Hallo aus dem Dateisystem!\nLinus haette das geliebt.\n'

img = bytearray(BLOCK * N_ZONES)

# --- Block 1: Superblock (20 verwendete Bytes) ---------------------------
struct.pack_into('<HHHHHHIHH', img, BLOCK,
    N_INODES, N_ZONES, N_IMAP, N_ZMAP,
    FIRST_DATA, 0, 0x10081C00, MAGIC_V1_14, 1)

# --- Block 2: Inode-Bitmap (Bit 0 = NULL, Bit 1 = root, Bit 2 = hello.txt) -
img[2*BLOCK] = 0b00000111
for i in range(1, BLOCK):
    img[2*BLOCK + i] = 0xFF

# --- Block 3: Zone-Bitmap (Bit 0 = NULL, Bit 1 = root dir, Bit 2 = hello.txt) -
img[3*BLOCK] = 0b00000111
for i in range(1, BLOCK):
    img[3*BLOCK + i] = 0xFF

# --- Block 4: Inode-Tabelle ---------------------------------------------
INODES = 4 * BLOCK

# Inode 1: Root-Verzeichnis (mode = dir 0755, 3 Dir-Eintraege)
struct.pack_into('<HHIIBB9H', img, INODES + 0*32,
    0o040755, 0, 3*16, int(time.time()), 0, 2,
    FIRST_DATA, 0,0,0,0,0,0,0,0)

# Inode 2: hello.txt (mode = file 0644)
struct.pack_into('<HHIIBB9H', img, INODES + 1*32,
    0o100644, 0, len(HELLO), int(time.time()), 0, 1,
    FIRST_DATA + 1, 0,0,0,0,0,0,0,0)

# --- Block FIRST_DATA: Root-Dir-Eintraege (16 Byte je: 2 Inode + 14 Name) -
def de(ino, name):
    return struct.pack('<H14s', ino, name.encode().ljust(14, b'\x00'))
ROOT = FIRST_DATA * BLOCK
img[ROOT:ROOT+16] = de(1, '.')
img[ROOT+16:ROOT+32] = de(1, '..')
img[ROOT+32:ROOT+48] = de(2, 'hello.txt')

# --- Block FIRST_DATA+1: Inhalt von hello.txt ---------------------------
HELLO_OFF = (FIRST_DATA + 1) * BLOCK
img[HELLO_OFF:HELLO_OFF + len(HELLO)] = HELLO

with open(sys.argv[1], 'wb') as f:
    f.write(img)
PYEOF
