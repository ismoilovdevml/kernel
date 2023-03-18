```bash
$ dd if=/dev/zero of=test.img bs=512 count=2880
2880+0 records in
2880+0 records out
1474560 bytes (1.5 MB, 1.4 MiB) copied, 0.0237028 s, 62.2 MB/s
$ mkfs.fat -F 12 -n "NBOS" test.img 
mkfs.fat 4.2 (2021-01-31)
$ mcopy -i test.img build/kernel.bin "::kernel.bin"
```
