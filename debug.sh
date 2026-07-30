#!/usr/bin/env sh
#
# Boot the image in QEMU with the CPU stopped, waiting for a debugger on
# localhost:1234. In another terminal:
#
#   gdb -ex 'set architecture i8086' -ex 'target remote localhost:1234'
#   (gdb) break *0x7c00      # the boot sector
#   (gdb) break *0x20000     # the kernel entry point
#
# Bochs can be used instead:  bochs -f bochs_config
#
set -e
cd "$(dirname "$0")"

make floppy_image
echo "QEMU is waiting for a debugger on localhost:1234 ..."
exec qemu-system-i386 -fda build/main_floppy.img -s -S "$@"
