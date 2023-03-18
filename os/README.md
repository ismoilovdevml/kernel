```bash
$ dd if=/dev/zero of=test.img bs=512 count=2880
2880+0 records in
2880+0 records out
1474560 bytes (1.5 MB, 1.4 MiB) copied, 0.0237028 s, 62.2 MB/s
$ mkfs.fat -F 12 -n "NBOS" test.img 
mkfs.fat 4.2 (2021-01-31)
$ mcopy -i test.img build/kernel.bin "::kernel.bin"
```

```bash
$ make
mkdir -p build
nasm src/bootloader/boot.asm -f bin -o build/bootloader.bin
nasm src/kernel/main.asm -f bin -o build/kernel.bin
dd if=/dev/zero of=build/main_floppy.img bs=512 count=2880
2880+0 records in
2880+0 records out
1474560 bytes (1.5 MB, 1.4 MiB) copied, 0.0111259 s, 133 MB/s
mkfs.fat -F 12 -n "NBOS" build/main_floppy.img
mkfs.fat 4.2 (2021-01-31)
dd if=build/bootloader.bin of=build/main_floppy.img conv=notrunc
1+0 records in
1+0 records out
512 bytes copied, 7.5683e-05 s, 6.8 MB/s
mcopy -i build/main_floppy.img build/kernel.bin "::kernel.bin"


$ mdir -i build/main_floppy.img 
 Volume in drive : is NBOS       
 Volume Serial Number is 7856-3412
Directory for ::/

kernel   bin       512 2023-03-18  11:23 
        1 file                  512 bytes
                          1 457 152 bytes free
```