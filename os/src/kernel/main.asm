org 0x7C00
bits 16

%define ENDL 0x00, 0x0A


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

msg_salom: db 'Salom Dasturchi', ENDL, 0


times 510-($-$$) db 0
dw 0xAA55
