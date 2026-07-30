/*
 * VGA text mode driver.
 *
 * In protected mode there is no BIOS to call, so output means writing
 * character/attribute pairs straight into the framebuffer at 0xB8000 and
 * driving the hardware cursor through the CRT controller's index/data port
 * pair.
 */

#include "vga.h"
#include "io.h"

#define VGA_MEMORY  ((volatile uint16_t *)0xB8000)
#define VGA_COLS    80
#define VGA_ROWS    25
#define TAB_WIDTH   4

#define CRTC_INDEX  0x3D4
#define CRTC_DATA   0x3D5

static uint16_t cursor_row;
static uint16_t cursor_col;
static uint8_t  attribute;

static inline uint16_t vga_cell(char c)
{
    return (uint16_t)c | ((uint16_t)attribute << 8);
}

static void vga_move_cursor(void)
{
    uint16_t pos = cursor_row * VGA_COLS + cursor_col;

    outb(CRTC_INDEX, 0x0F);             /* cursor location low */
    outb(CRTC_DATA, (uint8_t)(pos & 0xFF));
    outb(CRTC_INDEX, 0x0E);             /* cursor location high */
    outb(CRTC_DATA, (uint8_t)(pos >> 8));
}

static void vga_scroll(void)
{
    volatile uint16_t *mem = VGA_MEMORY;

    for (int i = 0; i < (VGA_ROWS - 1) * VGA_COLS; i++) {
        mem[i] = mem[i + VGA_COLS];
    }

    for (int i = (VGA_ROWS - 1) * VGA_COLS; i < VGA_ROWS * VGA_COLS; i++) {
        mem[i] = vga_cell(' ');
    }

    cursor_row = VGA_ROWS - 1;
}

static void vga_newline(void)
{
    cursor_col = 0;
    if (++cursor_row >= VGA_ROWS) {
        vga_scroll();
    }
}

void vga_set_color(enum vga_color fg, enum vga_color bg)
{
    attribute = (uint8_t)fg | (uint8_t)(bg << 4);
}

void vga_clear(void)
{
    volatile uint16_t *mem = VGA_MEMORY;

    for (int i = 0; i < VGA_ROWS * VGA_COLS; i++) {
        mem[i] = vga_cell(' ');
    }

    cursor_row = 0;
    cursor_col = 0;
    vga_move_cursor();
}

void vga_init(void)
{
    vga_set_color(VGA_LIGHT_GREY, VGA_BLACK);
    vga_clear();
}

void vga_putchar(char c)
{
    switch (c) {
    case '\n':
        vga_newline();
        break;

    case '\r':
        cursor_col = 0;
        break;

    case '\b':
        if (cursor_col > 0) {
            cursor_col--;
        } else if (cursor_row > 0) {
            cursor_row--;
            cursor_col = VGA_COLS - 1;
        }
        VGA_MEMORY[cursor_row * VGA_COLS + cursor_col] = vga_cell(' ');
        break;

    case '\t':
        do {
            vga_putchar(' ');
        } while (cursor_col % TAB_WIDTH != 0);
        return;                         /* the recursion already moved the cursor */

    default:
        VGA_MEMORY[cursor_row * VGA_COLS + cursor_col] = vga_cell(c);
        if (++cursor_col >= VGA_COLS) {
            vga_newline();
        }
        break;
    }

    vga_move_cursor();
}

void vga_puts(const char *s)
{
    while (*s) {
        vga_putchar(*s++);
    }
}

void vga_put_dec(uint32_t value)
{
    char buffer[11];
    int i = 0;

    if (value == 0) {
        vga_putchar('0');
        return;
    }

    while (value > 0) {
        buffer[i++] = (char)('0' + value % 10);
        value /= 10;
    }

    while (i > 0) {
        vga_putchar(buffer[--i]);
    }
}

void vga_put_dec_padded(uint32_t value, int width)
{
    uint32_t digits = 1;
    for (uint32_t v = value; v >= 10; v /= 10) {
        digits++;
    }

    for (int i = (int)digits; i < width; i++) {
        vga_putchar(' ');
    }

    vga_put_dec(value);
}

static void put_hex_nibbles(uint64_t value, int nibbles)
{
    static const char digits[] = "0123456789ABCDEF";

    for (int shift = (nibbles - 1) * 4; shift >= 0; shift -= 4) {
        vga_putchar(digits[(value >> shift) & 0xF]);
    }
}

void vga_put_hex32(uint32_t value)
{
    put_hex_nibbles(value, 8);
}

void vga_put_hex64(uint64_t value)
{
    put_hex_nibbles(value, 16);
}
