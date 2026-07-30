/*
 * The kernel is linked to run at 1 MiB. Stage 2 reads it into low memory with
 * BIOS calls and copies it here once protected mode is on.
 */

ENTRY(_start)

SECTIONS
{
    . = 0x00100000;

    /* the entry stub has to be the very first thing in the image, because
       stage 2 jumps straight at the load address */
    .text : ALIGN(4K)
    {
        *(.entry)
        *(.text*)
    }

    .rodata : ALIGN(4K)
    {
        *(.rodata*)
    }

    .data : ALIGN(4K)
    {
        *(.data*)
    }

    /* .bss occupies no space in the image, the entry stub zeroes it */
    .bss : ALIGN(4K)
    {
        __bss_start = .;
        *(COMMON)
        *(.bss*)
        __bss_end = .;
    }

    __kernel_end = .;

    /DISCARD/ :
    {
        *(.comment)
        *(.note*)
        *(.eh_frame)
    }
}
