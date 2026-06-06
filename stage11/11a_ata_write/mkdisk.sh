#!/bin/sh
# 11a: leere 2-MB-Disk; der Test schreibt selbst in Sektor 5.
set -e
dd if=/dev/zero of="$1" bs=1M count=2 status=none
