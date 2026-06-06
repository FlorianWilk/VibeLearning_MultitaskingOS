#!/bin/sh
# 10c: Disk mit Text bei Sektor 1 (Byte 512), den proc_a per IRQ14 liest.
set -e
dd if=/dev/zero of="$1" bs=1M count=2 status=none
printf 'Hallo von Sektor 1 (per IRQ14 gelesen)!\n' | \
    dd of="$1" bs=1 seek=512 conv=notrunc status=none
