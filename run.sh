#!/usr/bin/env sh
#
# Build the floppy image (if needed) and boot it in QEMU.
#
set -e
cd "$(dirname "$0")"

make floppy_image
exec qemu-system-i386 -fda build/main_floppy.img "$@"
