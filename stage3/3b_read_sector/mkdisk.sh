#!/bin/sh
# 3b: 10 MB Disk mit Test-Pattern bei Sektor 0:
# inkrementierende Bytes 00 01 02 ... 3F -- 64 Stueck.
# Macht den Hex-Dump auf einen Blick verifizierbar.
set -e
dd if=/dev/zero of="$1" bs=1M count=10 status=none
python3 -c "import sys; sys.stdout.buffer.write(bytes(range(64)))" | \
    dd of="$1" bs=1 count=64 conv=notrunc status=none
