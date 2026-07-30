#ifndef VGA_H
#define VGA_H

#include <stdint.h>

enum vga_color {
    VGA_BLACK         = 0,
    VGA_BLUE          = 1,
    VGA_GREEN         = 2,
    VGA_CYAN          = 3,
    VGA_RED           = 4,
    VGA_MAGENTA       = 5,
    VGA_BROWN         = 6,
    VGA_LIGHT_GREY    = 7,
    VGA_DARK_GREY     = 8,
    VGA_LIGHT_BLUE    = 9,
    VGA_LIGHT_GREEN   = 10,
    VGA_LIGHT_CYAN    = 11,
    VGA_LIGHT_RED     = 12,
    VGA_LIGHT_MAGENTA = 13,
    VGA_YELLOW        = 14,
    VGA_WHITE         = 15,
};

void vga_init(void);
void vga_clear(void);
void vga_set_color(enum vga_color fg, enum vga_color bg);
void vga_putchar(char c);
void vga_puts(const char *s);

void vga_put_dec(uint32_t value);
void vga_put_hex32(uint32_t value);
void vga_put_hex64(uint64_t value);

/* Prints value padded with spaces on the left so it occupies `width` columns. */
void vga_put_dec_padded(uint32_t value, int width);

#endif
