;
; Stage 2 - the part of the bootloader that is not limited to 512 bytes.
;
; Loaded by the boot sector at 0x0000:0x0500 with the boot drive in DL. It
; enables the A20 line, asks the BIOS for the memory map, loads KERNEL.BIN from
; the FAT12 filesystem and hands control over to it.
;

org 0x500
bits 16

%define ENDL 0x0D, 0x0A

;
; The boot sector is still resident at 0x7C00, so we read the BPB straight out
; of it. Stage 1 already patched the geometry fields with the values the BIOS
; reported, so these are the trustworthy ones.
;
BPB                     equ 0x7C00
bpb_bytes_per_sector    equ BPB + 11
bpb_sectors_per_cluster equ BPB + 13
bpb_reserved_sectors    equ BPB + 14
bpb_fat_count           equ BPB + 16
bpb_dir_entries_count   equ BPB + 17
bpb_sectors_per_fat     equ BPB + 22
bpb_sectors_per_track   equ BPB + 24
bpb_heads               equ BPB + 26
ebr_drive_number        equ BPB + 36

;
; Memory layout we impose:
;
;   0x00500 - 0x07BFF   stage 2 (this code)
;   0x07C00 - 0x07DFF   boot sector, kept for its BPB
;   0x08000 - 0x08FFF   BIOS memory map handed to the kernel
;   0x0A000 - 0x0BFFF   scratch buffer for the root directory and the FAT
;   0x20000 - ...       the kernel
;
MEMMAP_COUNT            equ 0x8000      ; word: number of entries that follow
MEMMAP_DRIVE            equ 0x8002      ; word: the drive we booted from
MEMMAP_ENTRIES          equ 0x8004      ; 24 bytes per entry
MEMMAP_MAX              equ 64

DISK_BUFFER             equ 0xA000

; The kernel is read into low memory with BIOS calls, then copied to 1 MiB once
; we are in protected mode and the whole address space is reachable.
KERNEL_LOAD_SEGMENT     equ 0x2000
KERNEL_LOAD_OFFSET      equ 0x0000
KERNEL_STAGING          equ 0x20000
KERNEL_BASE             equ 0x100000
PM_STACK_TOP            equ 0x90000


start:
    ; the boot sector jumped here with CS = 0, normalize the rest
    xor ax, ax
    mov ds, ax
    mov es, ax

    cli
    mov ss, ax
    mov sp, 0x7C00              ; grows down, away from the boot sector
    sti

    mov [ebr_drive_number], dl  ; stage 1 stored it too, but be explicit

    mov si, msg_stage2
    call puts

    ;
    ; A20: without it every address above 1 MiB wraps around, which would
    ; silently corrupt memory as soon as we leave real mode.
    ;
    call enable_a20
    jc .a20_failed

    mov si, msg_a20_ok
    call puts
    jmp .a20_done

.a20_failed:
    mov si, msg_a20_fail
    call puts

.a20_done:
    ;
    ; Memory map: this has to happen here, because int 15h is a BIOS service
    ; and stops being reachable once we switch to protected mode.
    ;
    call detect_memory

    mov si, msg_memmap
    call puts
    mov ax, [MEMMAP_COUNT]
    call print_dec
    mov si, msg_memmap_tail
    call puts

    ;
    ; Load the kernel.
    ;
    mov si, msg_loading_kernel
    call puts

    mov si, file_kernel_bin
    mov ax, KERNEL_LOAD_SEGMENT
    mov bx, KERNEL_LOAD_OFFSET
    call fat_load_file

    mov si, msg_ok
    call puts

    ; the kernel finds the boot drive next to the memory map
    xor ax, ax
    mov al, [ebr_drive_number]
    mov [MEMMAP_DRIVE], ax

    mov si, msg_pmode
    call puts

    ;
    ; This is the last thing we do in real mode: from here on there are no
    ; BIOS services, so everything the kernel needs is already in memory.
    ;
    cli                         ; no IVT means no interrupts may fire
    lgdt [gdt_descriptor]

    mov eax, cr0
    or eax, 1                   ; set the protection enable bit
    mov cr0, eax

    jmp dword GDT_CODE32:pm_entry   ; far jump reloads CS with a 32-bit selector


bits 32

pm_entry:
    ; every segment register still holds a real mode value, replace them with
    ; the flat 4 GiB data selector
    mov ax, GDT_DATA32
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, PM_STACK_TOP

    ; move the kernel from where the BIOS could reach it up to 1 MiB
    mov esi, KERNEL_STAGING
    mov edi, KERNEL_BASE
    mov ecx, [kernel_size]
    add ecx, 3                  ; round up to whole dwords
    shr ecx, 2
    rep movsd

    jmp KERNEL_BASE

bits 16


;
; ---------------------------------------------------------------------------
; Output
; ---------------------------------------------------------------------------
;

;
; Prints a null terminated string.
; Params:
;   - ds:si points to the string
;
puts:
    push si
    push ax
    push bx

.loop:
    lodsb
    or al, al
    jz .done

    mov ah, 0x0E
    mov bh, 0
    int 0x10
    jmp .loop

.done:
    pop bx
    pop ax
    pop si
    ret


;
; Prints an unsigned 16-bit number in decimal.
; Params:
;   - ax: value
;
print_dec:
    push ax
    push bx
    push cx
    push dx

    mov bx, 10
    xor cx, cx

.divide:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .divide

.emit:
    pop ax
    add al, '0'
    mov ah, 0x0E
    push bx
    mov bh, 0
    int 0x10
    pop bx
    loop .emit

    pop dx
    pop cx
    pop bx
    pop ax
    ret


;
; ---------------------------------------------------------------------------
; A20 line
; ---------------------------------------------------------------------------
;

;
; Checks whether the A20 line is enabled.
; Returns:
;   - CF clear if A20 is enabled, set if it is disabled
;
; The test writes two different bytes to a pair of addresses exactly 1 MiB
; apart. With A20 masked off the second address wraps onto the first, so both
; reads return the same value.
;
check_a20:
    push ds
    push es
    push ax
    push bx
    push di
    push si

    xor ax, ax
    mov es, ax
    mov di, 0x7DFE              ; 0000:7DFE -> physical 0x007DFE

    not ax                      ; ax = 0xFFFF
    mov ds, ax
    mov si, 0x7E0E              ; FFFF:7E0E -> physical 0x107DFE

    mov bh, [es:di]             ; keep the original bytes
    mov bl, [ds:si]

    mov byte [es:di], 0x00
    mov byte [ds:si], 0xFF

    mov al, [es:di]             ; reads back 0xFF only if the two addresses alias

    mov [ds:si], bl             ; put the originals back
    mov [es:di], bh

    cmp al, 0xFF
    je .disabled

    clc                         ; different values -> A20 is on
    jmp .done

.disabled:
    stc

.done:
    pop si
    pop di
    pop bx
    pop ax
    pop es
    pop ds
    ret


;
; Enables the A20 line, trying every method in turn.
; Returns:
;   - CF clear on success
;
enable_a20:
    call check_a20              ; a lot of machines boot with it already on
    jnc .done

    mov ax, 0x2401              ; method 1: ask the BIOS
    int 0x15
    call check_a20
    jnc .done

    call a20_keyboard           ; method 2: the keyboard controller
    call check_a20
    jnc .done

    in al, 0x92                 ; method 3: the "fast A20" port
    test al, 2
    jnz .fast_done
    or al, 2
    and al, 0xFE                ; bit 0 triggers a reset, never set it
    out 0x92, al

.fast_done:
    call check_a20

.done:
    ret


;
; Enables A20 through the keyboard controller. Every wait is bounded so a
; machine without a working controller cannot hang us forever.
;
a20_keyboard:
    pusha
    cli

    call .wait_input
    mov al, 0xAD                ; disable the keyboard
    out 0x64, al

    call .wait_input
    mov al, 0xD0                ; read the output port
    out 0x64, al

    call .wait_output
    in al, 0x60
    push ax

    call .wait_input
    mov al, 0xD1                ; write the output port
    out 0x64, al

    call .wait_input
    pop ax
    or al, 2                    ; bit 1 is the A20 gate
    out 0x60, al

    call .wait_input
    mov al, 0xAE                ; enable the keyboard again
    out 0x64, al

    call .wait_input
    sti
    popa
    ret

.wait_input:                    ; wait for the input buffer to drain
    push cx
    mov cx, 0xFFFF
.wait_input_loop:
    in al, 0x64
    test al, 2
    jz .wait_input_done
    loop .wait_input_loop
.wait_input_done:
    pop cx
    ret

.wait_output:                   ; wait for a byte to show up in the output buffer
    push cx
    mov cx, 0xFFFF
.wait_output_loop:
    in al, 0x64
    test al, 1
    jnz .wait_output_done
    loop .wait_output_loop
.wait_output_done:
    pop cx
    ret


;
; ---------------------------------------------------------------------------
; Memory map
; ---------------------------------------------------------------------------
;

;
; Collects the BIOS memory map with int 15h / E820 into MEMMAP_ENTRIES and
; stores the entry count at MEMMAP_COUNT. Each entry is 24 bytes:
;   base (8) | length (8) | type (4) | ACPI attributes (4)
;
detect_memory:
    pusha
    push es

    xor ax, ax
    mov es, ax
    mov word [MEMMAP_COUNT], 0

    mov di, MEMMAP_ENTRIES
    xor ebx, ebx                ; continuation value, 0 starts a new walk
    xor bp, bp                  ; entries stored so far

.loop:
    mov eax, 0xE820
    mov edx, 0x534D4150         ; 'SMAP'
    mov ecx, 24
    mov dword [es:di + 20], 1   ; make ACPI 3 BIOSes mark the entry as valid
    int 0x15

    jc .done                    ; carry on the first call means E820 is missing
    cmp eax, 0x534D4150
    jne .done

    ; drop zero length entries, they carry no information
    mov ecx, [es:di + 8]
    or ecx, [es:di + 12]
    jz .skip

    inc bp
    add di, 24

.skip:
    test ebx, ebx               ; zero continuation means that was the last one
    jz .done
    cmp bp, MEMMAP_MAX
    jb .loop

.done:
    mov [MEMMAP_COUNT], bp

    pop es
    popa
    ret


;
; ---------------------------------------------------------------------------
; FAT12
; ---------------------------------------------------------------------------
;

;
; Loads a file from the FAT12 volume.
; Params:
;   - ds:si: 11 byte 8.3 name, e.g. 'KERNEL  BIN'
;   - ax:    destination segment
;   - bx:    destination offset
;
fat_load_file:
    mov [dest_segment], ax
    mov [dest_offset], bx
    mov [name_ptr], si

    ;
    ; root_dir_lba = reserved_sectors + fat_count * sectors_per_fat
    ;
    mov ax, [bpb_sectors_per_fat]
    mov bl, [bpb_fat_count]
    xor bh, bh
    mul bx
    add ax, [bpb_reserved_sectors]
    mov [root_dir_lba], ax

    ;
    ; root_dir_sectors = ceil(dir_entries * 32 / bytes_per_sector)
    ;
    mov ax, [bpb_dir_entries_count]
    shl ax, 5
    xor dx, dx
    div word [bpb_bytes_per_sector]

    test dx, dx
    jz .root_dir_after
    inc ax

.root_dir_after:
    ; the data region begins right after the root directory
    mov bx, [root_dir_lba]
    add bx, ax
    mov [data_region_lba], bx

    ; read the root directory into the scratch buffer
    push ax
    xor ax, ax
    mov es, ax                  ; the buffer lives in segment 0
    pop cx                      ; cx = sectors to read
    mov ax, [root_dir_lba]
    mov dl, [ebr_drive_number]
    mov bx, DISK_BUFFER
    call disk_read

    ;
    ; scan the root directory for our file
    ;
    xor bx, bx
    mov di, DISK_BUFFER

.search:
    mov si, [name_ptr]
    mov cx, 11
    push di
    repe cmpsb
    pop di
    je .found

    add di, 32
    inc bx
    cmp bx, [bpb_dir_entries_count]
    jl .search

    mov si, msg_no_file
    jmp error

.found:
    mov ax, [di + 26]           ; first cluster
    mov [file_cluster], ax

    mov eax, [di + 28]          ; exact file size in bytes
    mov [kernel_size], eax

    ; read the FAT into the same buffer, we are done with the directory
    mov ax, [bpb_reserved_sectors]
    mov cl, [bpb_sectors_per_fat]
    mov dl, [ebr_drive_number]
    mov bx, DISK_BUFFER
    call disk_read

    ; from here on es:bx points at the destination
    mov es, [dest_segment]
    mov bx, [dest_offset]

.load_loop:
    ; cluster_lba = data_region_lba + (cluster - 2) * sectors_per_cluster
    mov ax, [file_cluster]
    sub ax, 2
    xor ch, ch
    mov cl, [bpb_sectors_per_cluster]
    mul cx
    add ax, [data_region_lba]

    mov dl, [ebr_drive_number]
    call disk_read              ; preserves cx, still the cluster size

    ; advance by one cluster, carrying into es across the 64 KiB boundary
    mov ax, [bpb_bytes_per_sector]
    mul cx
    add bx, ax
    jnc .next_cluster

    mov ax, es
    add ax, 0x1000
    mov es, ax

.next_cluster:
    ; FAT12 entry for a cluster starts at byte offset cluster * 3 / 2
    mov ax, [file_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx                      ; ax = offset, dx = cluster & 1

    mov si, DISK_BUFFER
    add si, ax
    mov ax, [ds:si]

    or dx, dx
    jz .even

.odd:
    shr ax, 4
    jmp .check_end

.even:
    and ax, 0x0FFF

.check_end:
    cmp ax, 0x0FF8
    jae .finished

    mov [file_cluster], ax
    jmp .load_loop

.finished:
    ret


;
; ---------------------------------------------------------------------------
; Disk
; ---------------------------------------------------------------------------
;

;
; Converts an LBA address to CHS.
; Params:
;   - ax: LBA
; Returns:
;   - cx [bits 0-5]: sector, cx [bits 6-15]: cylinder, dh: head
;
lba_to_chs:
    push ax
    push dx

    xor dx, dx
    div word [bpb_sectors_per_track]

    inc dx
    mov cx, dx

    xor dx, dx
    div word [bpb_heads]
    mov dh, dl
    mov ch, al
    shl ah, 6
    or cl, ah

    pop ax
    mov dl, al
    pop ax
    ret


;
; Reads sectors from a disk.
; Params:
;   - ax: LBA, cl: sector count, dl: drive, es:bx: destination
;
disk_read:
    push ax
    push bx
    push cx
    push dx
    push di

    push cx
    call lba_to_chs
    pop ax

    mov ah, 02h
    mov di, 3

.retry:
    pusha
    stc
    int 13h
    jnc .done

    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

    mov si, msg_disk_err
    jmp error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret


;
; Resets the disk controller.
; Params:
;   - dl: drive number
;
disk_reset:
    pusha
    xor ah, ah
    stc
    int 13h
    jc .failed
    popa
    ret

.failed:
    mov si, msg_disk_err
    jmp error


;
; Prints ds:si and reboots after a keypress.
;
error:
    call puts
    mov si, msg_press_key
    call puts
    xor ah, ah
    int 16h
    jmp 0FFFFh:0


;
; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
;

;
; A flat GDT: both descriptors cover the whole 4 GiB address space, so once we
; are in protected mode a segment register is just a permission tag and every
; pointer is a plain linear address.
;
align 8
gdt_start:
    dq 0                        ; the null descriptor, required to be first

gdt_code32:                     ; selector 0x08
    dw 0xFFFF                   ; limit  0:15
    dw 0                        ; base   0:15
    db 0                        ; base  16:23
    db 10011010b                ; present, ring 0, code, readable
    db 11001111b                ; 4 KiB granularity, 32-bit, limit 16:19
    db 0                        ; base  24:31

gdt_data32:                     ; selector 0x10
    dw 0xFFFF
    dw 0
    db 0
    db 10010010b                ; present, ring 0, data, writable
    db 11001111b
    db 0
gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1  ; size of the table minus one
    dd gdt_start                ; linear address of the table

GDT_CODE32          equ gdt_code32 - gdt_start
GDT_DATA32          equ gdt_data32 - gdt_start


msg_stage2:         db 'Stage2 loaded', ENDL, 0
msg_a20_ok:         db '  A20 enabled', ENDL, 0
msg_a20_fail:       db '  A20 could NOT be enabled', ENDL, 0
msg_memmap:         db '  memory map: ', 0
msg_memmap_tail:    db ' regions', ENDL, 0
msg_loading_kernel: db '  loading KERNEL.BIN ...', 0
msg_ok:             db ' ok', ENDL, 0
msg_pmode:          db '  entering protected mode', ENDL, 0
msg_no_file:        db ENDL, 'File not found on the boot volume!', ENDL, 0
msg_disk_err:       db ENDL, 'Disk read failed!', ENDL, 0
msg_press_key:      db 'Press any key to reboot...', ENDL, 0

file_kernel_bin:    db 'KERNEL  BIN'

; runtime state
name_ptr:           dw 0
dest_segment:       dw 0
dest_offset:        dw 0
root_dir_lba:       dw 0
data_region_lba:    dw 0
file_cluster:       dw 0
kernel_size:        dd 0        ; exact byte count, taken from the directory entry
