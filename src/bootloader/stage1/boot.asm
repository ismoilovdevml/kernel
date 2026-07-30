;
; Stage 1 - the boot sector.
;
; The BIOS only ever loads these 512 bytes, so everything here is spent on the
; smallest job that still gets us going: parse enough FAT12 to find STAGE2.BIN,
; load it at 0x0000:0x0500 and jump to it. Stage 2 has no size limit and does
; all the real work.
;
; The boot sector stays resident at 0x7C00 afterwards, so stage 2 reads the BPB
; (including the drive geometry patched in below) straight out of it.
;

org 0x7C00
bits 16


%define ENDL 0x0D, 0x0A

STAGE2_LOAD_SEGMENT equ 0x0000
STAGE2_LOAD_OFFSET  equ 0x0500


;
; FAT12 header
;
jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'           ; 8 bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880                 ; 2880 * 512 = 1.44MB
bdb_media_descriptor_type:  db 0F0h                 ; F0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9                    ; 9 sectors/fat
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; extended boot record
ebr_drive_number:           db 0                    ; 0x00 floppy, 0x80 hdd
                            db 0                    ; reserved
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h   ; serial number, value doesn't matter
ebr_volume_label:           db 'NANOBYTE OS'        ; 11 bytes, padded with spaces
ebr_system_id:              db 'FAT12   '           ; 8 bytes

;
; Code goes here
;

start:
    ; setup data segments
    xor ax, ax                  ; can't set ds/es directly
    mov ds, ax
    mov es, ax

    ; setup stack, it grows downwards from where we are loaded in memory
    mov ss, ax
    mov sp, 0x7C00

    ; some BIOSes enter at 07C0:0000 instead of 0000:7C00, so normalize CS:IP
    ; with a far return before touching any absolute label
    push ax                     ; CS = 0
    push word .after
    retf

.after:
    ; BIOS passes the boot drive number in DL
    mov [ebr_drive_number], dl

    mov si, msg_loading
    call puts

    ; read the real drive geometry from the BIOS instead of trusting the
    ; values stored on the formatted disk. Stage 2 reuses the patched values.
    push es
    mov ah, 08h
    xor di, di                  ; guard against buggy BIOSes: es:di = 0000:0000
    int 13h
    jc disk_error
    pop es

    and cl, 0x3F                ; drop the top 2 bits, they belong to the cylinder
    xor ch, ch
    mov [bdb_sectors_per_track], cx

    inc dh                      ; head count = highest head index + 1
    mov [bdb_heads], dh

    ;
    ; root_dir_lba = reserved_sectors + fat_count * sectors_per_fat
    ;
    mov ax, [bdb_sectors_per_fat]
    mov bl, [bdb_fat_count]
    xor bh, bh
    mul bx
    add ax, [bdb_reserved_sectors]
    push ax                     ; save the root directory LBA

    ;
    ; root_dir_sectors = ceil(dir_entries * 32 / bytes_per_sector)
    ;
    mov ax, [bdb_dir_entries_count]
    shl ax, 5                   ; ax = dir_entries * 32
    xor dx, dx
    div word [bdb_bytes_per_sector]

    test dx, dx                 ; remainder != 0 -> round up
    jz .root_dir_after
    inc ax

.root_dir_after:
    mov cl, al                  ; cl = sectors occupied by the root directory
    pop ax                      ; ax = root directory LBA

    ; the data region starts right after the root directory
    mov bx, ax
    add bl, cl
    adc bh, 0
    mov [data_region_lba], bx

    ; read the root directory into the scratch buffer
    mov dl, [ebr_drive_number]
    mov bx, buffer
    call disk_read

    ;
    ; look for STAGE2.BIN among the root directory entries
    ;
    xor bx, bx                  ; bx = entry index
    mov di, buffer

.search_file:
    mov si, file_stage2_bin
    mov cx, 11                  ; an 8.3 name is 11 bytes
    push di
    repe cmpsb
    pop di
    je .found_file

    add di, 32                  ; move on to the next directory entry
    inc bx
    cmp bx, [bdb_dir_entries_count]
    jl .search_file

    jmp stage2_not_found_error

.found_file:
    mov ax, [di + 26]           ; offset 26 holds the first cluster of the file
    mov [file_cluster], ax

    ; read the whole FAT into the scratch buffer
    mov ax, [bdb_reserved_sectors]
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_drive_number]
    mov bx, buffer
    call disk_read

    ; destination of the stage 2 image
    mov ax, STAGE2_LOAD_SEGMENT
    mov es, ax
    mov bx, STAGE2_LOAD_OFFSET

;
; Walk the FAT cluster chain and load every cluster of stage 2.
;
.load_loop:
    ; cluster_lba = data_region_lba + (cluster - 2) * sectors_per_cluster
    mov ax, [file_cluster]
    sub ax, 2
    xor ch, ch
    mov cl, [bdb_sectors_per_cluster]
    mul cx
    add ax, [data_region_lba]

    mov dl, [ebr_drive_number]
    call disk_read              ; preserves CX, so it still holds the cluster size

    ; advance the destination pointer by one cluster, moving ES forward when
    ; the offset wraps around the 64 KiB segment boundary
    mov ax, [bdb_bytes_per_sector]
    mul cx                      ; ax = bytes per cluster
    add bx, ax
    jnc .next_cluster

    mov ax, es
    add ax, 0x1000
    mov es, ax

.next_cluster:
    ;
    ; FAT12 packs two 12-bit entries into three bytes, so the byte offset of
    ; an entry is cluster * 3 / 2.
    ;
    mov ax, [file_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx                      ; ax = byte offset, dx = cluster & 1

    mov si, buffer
    add si, ax
    mov ax, [ds:si]             ; the 16 bits that contain our entry

    or dx, dx
    jz .even

.odd:
    shr ax, 4                   ; odd cluster -> upper 12 bits
    jmp .next_cluster_after

.even:
    and ax, 0x0FFF              ; even cluster -> lower 12 bits

.next_cluster_after:
    cmp ax, 0x0FF8              ; 0xFF8 and above mark the end of the chain
    jae .read_finish

    mov [file_cluster], ax
    jmp .load_loop

.read_finish:
    ; hand the boot drive number over to stage 2 in DL
    mov dl, [ebr_drive_number]
    jmp STAGE2_LOAD_SEGMENT:STAGE2_LOAD_OFFSET


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
    lodsb                       ; load the next character into al
    or al, al                   ; null terminator?
    jz .done

    mov ah, 0x0E                ; BIOS teletype output
    mov bh, 0                   ; page 0
    int 0x10
    jmp .loop

.done:
    pop bx
    pop ax
    pop si
    ret


;
; Error handlers
;

stage2_not_found_error:
    mov si, msg_no_stage2
    jmp error

disk_error:
    mov si, msg_disk_err

error:
    call puts
    xor ah, ah
    int 16h                     ; wait for a keypress
    jmp 0FFFFh:0                ; jump to the BIOS entry point, this reboots


;
; Disk routines
;

;
; Converts an LBA address to a CHS address
; Parameters:
;   - ax: LBA address
; Returns:
;   - cx [bits 0-5]: sector number
;   - cx [bits 6-15]: cylinder
;   - dh: head
;
lba_to_chs:
    push ax
    push dx

    xor dx, dx                          ; dx = 0
    div word [bdb_sectors_per_track]    ; ax = LBA / SectorsPerTrack
                                        ; dx = LBA % SectorsPerTrack

    inc dx                              ; dx = (LBA % SectorsPerTrack + 1) = sector
    mov cx, dx                          ; cx = sector

    xor dx, dx                          ; dx = 0
    div word [bdb_heads]                ; ax = (LBA / SectorsPerTrack) / Heads = cylinder
                                        ; dx = (LBA / SectorsPerTrack) % Heads = head
    mov dh, dl                          ; dh = head
    mov ch, al                          ; ch = cylinder (lower 8 bits)
    shl ah, 6
    or cl, ah                           ; put upper 2 bits of cylinder in CL

    pop ax
    mov dl, al                          ; restore DL
    pop ax
    ret


;
; Reads sectors from a disk
; Parameters:
;   - ax: LBA address
;   - cl: number of sectors to read (up to 128)
;   - dl: drive number
;   - es:bx: memory address where to store read data
;
disk_read:
    push ax                             ; save registers we will modify
    push bx
    push cx
    push dx
    push di

    push cx                             ; temporarily save CL (number of sectors to read)
    call lba_to_chs                     ; compute CHS
    pop ax                              ; AL = number of sectors to read

    mov ah, 02h
    mov di, 3                           ; retry count

.retry:
    pusha                               ; save all registers, we don't know what bios modifies
    stc                                 ; set carry flag, some BIOS'es don't set it
    int 13h                             ; carry flag cleared = success
    jnc .done                           ; jump if carry not set

    ; read failed
    popa
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    ; all attempts are exhausted
    jmp disk_error

.done:
    popa

    pop di
    pop dx
    pop cx
    pop bx
    pop ax                             ; restore registers modified
    ret


;
; Resets disk controller
; Parameters:
;   dl: drive number
;
disk_reset:
    pusha
    xor ah, ah
    stc
    int 13h
    jc disk_error
    popa
    ret


msg_loading:            db 'Boot ', 0
msg_disk_err:           db 'DiskErr', ENDL, 0
msg_no_stage2:          db 'NoStage2', ENDL, 0
file_stage2_bin:        db 'STAGE2  BIN'

; variables filled in at runtime
data_region_lba:        dw 0
file_cluster:           dw 0

times 510-($-$$) db 0
dw 0AA55h

; Scratch buffer, lives right after the boot sector at 0x7E00. Used for the
; root directory and then for the FAT; never written back to disk.
buffer:
