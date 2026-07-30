ASM=nasm
ASMFLAGS=-f bin

# The kernel is built with a cross compiler that targets bare i686, so nothing
# from the host's libc or dynamic loader can sneak into the image.
CC=i686-elf-gcc
OBJCOPY=i686-elf-objcopy

SRC_DIR=src
BUILD_DIR=build

QEMU=qemu-system-i386
FLOPPY=$(BUILD_DIR)/main_floppy.img

STAGE1=$(BUILD_DIR)/stage1.bin
STAGE2=$(BUILD_DIR)/stage2.bin
KERNEL=$(BUILD_DIR)/kernel.bin
KERNEL_ELF=$(BUILD_DIR)/kernel.elf
OBJ_DIR=$(BUILD_DIR)/kernel

CFLAGS=-std=gnu11 -ffreestanding -fno-pie -fno-stack-protector \
       -fno-omit-frame-pointer -Wall -Wextra -O2 -I$(SRC_DIR)/kernel
LDFLAGS=-T $(SRC_DIR)/kernel/linker.ld -nostdlib -Wl,--build-id=none

KERNEL_C_SRC=$(wildcard $(SRC_DIR)/kernel/*.c)
KERNEL_OBJ=$(OBJ_DIR)/entry.o $(patsubst $(SRC_DIR)/kernel/%.c,$(OBJ_DIR)/%.o,$(KERNEL_C_SRC))

# mtools is used instead of mkfs.fat so the build works on macOS as well as
# Linux; skipping its geometry check keeps it quiet about the plain image file
export MTOOLS_SKIP_CHECK=1

.PHONY: all floppy_image stage1 stage2 kernel bootloader run debug dump clean always

all: floppy_image

#
# Floppy image: a 1.44MB FAT12 filesystem with the boot sector in sector 0 and
# stage 2 plus the kernel stored as regular files.
#
floppy_image: $(FLOPPY)

$(FLOPPY): $(STAGE1) $(STAGE2) $(KERNEL)
	dd if=/dev/zero of=$(FLOPPY) bs=512 count=2880 2>/dev/null
	mformat -i $(FLOPPY) -f 1440 -v NBOS ::
	dd if=$(STAGE1) of=$(FLOPPY) conv=notrunc 2>/dev/null
	mcopy -i $(FLOPPY) $(STAGE2) "::STAGE2.BIN"
	mcopy -i $(FLOPPY) $(KERNEL) "::KERNEL.BIN"
	@echo "--- floppy image contents ---"
	@mdir -i $(FLOPPY)

#
# Bootloader: stage 1 is the 512 byte boot sector, stage 2 is loaded by it
#
bootloader: stage1 stage2

stage1: $(STAGE1)
stage2: $(STAGE2)

$(STAGE1): $(SRC_DIR)/bootloader/stage1/boot.asm | always
	$(ASM) $< $(ASMFLAGS) -o $@

$(STAGE2): $(SRC_DIR)/bootloader/stage2/main.asm | always
	$(ASM) $< $(ASMFLAGS) -o $@

#
# Kernel: C compiled to ELF, then flattened to a raw binary because stage 2
# copies it to 1 MiB and jumps straight at the first byte.
#
kernel: $(KERNEL)

$(KERNEL): $(KERNEL_ELF)
	$(OBJCOPY) -O binary $< $@

$(KERNEL_ELF): $(KERNEL_OBJ) $(SRC_DIR)/kernel/linker.ld
	$(CC) $(LDFLAGS) -o $@ $(KERNEL_OBJ) -lgcc

$(OBJ_DIR)/entry.o: $(SRC_DIR)/kernel/entry.asm | always
	$(ASM) $< -f elf32 -o $@

$(OBJ_DIR)/%.o: $(SRC_DIR)/kernel/%.c | always
	$(CC) $(CFLAGS) -c $< -o $@

#
# Boot the image in QEMU
#
run: $(FLOPPY)
	$(QEMU) -fda $(FLOPPY)

#
# Boot the image and wait for a debugger on localhost:1234
# (connect with: gdb -ex 'target remote localhost:1234')
#
debug: $(FLOPPY)
	$(QEMU) -fda $(FLOPPY) -s -S

#
# Hexdump of the boot sector, useful when the BPB looks suspicious
#
dump: $(STAGE1)
	hexdump -C $(STAGE1) | head -40

#
# Always
#
always:
	mkdir -p $(OBJ_DIR)

#
# Clean
#
clean:
	rm -rf $(BUILD_DIR)/*
