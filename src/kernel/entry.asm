;
; The first thing that runs in the kernel image.
;
; Stage 2 jumps here with protection enabled, a flat GDT loaded, every segment
; register pointing at the 4 GiB data descriptor and interrupts disabled. All
; that is left is to give C code a stack and a zeroed .bss.
;

bits 32

section .entry

global _start
extern kmain
extern __bss_start
extern __bss_end

_start:
    mov esp, kernel_stack_top
    mov ebp, esp

    ; C assumes uninitialized globals start out as zero
    mov edi, __bss_start
    mov ecx, __bss_end
    sub ecx, edi
    xor eax, eax
    rep stosb

    call kmain

    ; kmain is not supposed to return, but if it ever does, stop cleanly
.halt:
    cli
    hlt
    jmp .halt


section .bss
align 16
kernel_stack:
    resb 16384                  ; 16 KiB is plenty for what we do so far
kernel_stack_top:
