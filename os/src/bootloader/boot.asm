org 0x7C00
bits 16

%define ENDL 0x00, 0x0A

;
; FAT32 header
;

jmp short start
nop

bdb_oem:                    db 'MSWIN4.1' 			; 8bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:		dw 0E0h
bdb_total_sectors: 			dw 2880					; 2880 * 512 = 1.44MB
bdb_media_descriptor_type:	db 0F0h					; F0 = 3.5" floppy disk
bdb_sectors_per_fat:		dw 9 					; 9 sectors/fat
bdb_sectors_per_track:		dw 18
bdb_heads:					dw 2
bdb_hidden_sectors:			dd 0
bdb_large_sector_count:		dd 0

; extended boot record

ebr_drive_number:			db 0					; 0x00 floppy, 0x80 hdd,
							db 0					; reserved
ebr_signature:				db 29h
ebr_volume_id:				db 12h, 34h, 56h, 78h,	;serial number
ebr_volume_label:			db 'NANOBYTE OS'		; 11 bytes
ebr_system_id:				db 'FAT12	'			; 8 bytes




start:
	jmp main


puts:
	push si
	push ax

.loop:
	lodsb
	or al, al
	jz .done
	mov ah, 0x0e
	int 0x10

	jmp .loop

.done:
	pop ax
	pop si
	ret
	 
main:
	mov ax, 0
	mov ds, ax
	mov es, ax

	; setup stack
	mov ss, ax
	mov sp, 0x7C00

	mov si, msg_salom
	call puts

	hlt
	
.halt:
	jmp .halt

;
; Disk routines
;
;
; Converts an LBA address to a CHS address
; Parameters;
;	- ax: LDA address
; Returns;
;	- cx [bits 0-5]: sector number
;	- cx [bits 6-15]: cylinder
;	- dh: head
;

lba_to_chs:

	xor dx, dx							; dx = 0
	div word [bdb_sectors_per_track]	; ax = LBA / SectorPerTrack
										; dx = LBA % SectorPerTrack

	inc dx								; dx = (LBA % SectorPerTrack + 1) = sector
	mov cx, dx							; cx = sector

	xor dx, dx							; dx = 0
	diw word [bdb_heads]				; ax = (LBA / SectorsPerTrackk) / Heads = cylinder
										; dx = (LBA / SectorsPerTrack) % Heads = head

	mov dh, dl							; dh = head
	mov ch, al							; ch = cylinder
	shl ah, 6
	or cl, ah							; put upper 2 bits of cylinder in CL


msg_salom: db 'Hello Worls!', ENDL, 0


times 510-($-$$) db 0
dw 0xAA55
