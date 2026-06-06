#!/bin/sh
# 3a: Eine leere 10-MB-Disk reicht. Wir wollen die Hardware nur ERKENNEN.
# Spaeter (3c) baut hier ein Minix-FS-Image.
set -e
dd if=/dev/zero of="$1" bs=1M count=10 status=none
