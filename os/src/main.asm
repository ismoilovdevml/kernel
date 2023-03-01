org 0x7C00
bits 16






main:
	; etup data segments
	mov ax, 0
	mov ds, ax
	mov es, ax

	; setup stack
	mov ss, axmov sp, 0x7C00



	
	hlt
	
.halt:
	jmp .halt


times 510-($-$$) db 0
dw 0AA55h
