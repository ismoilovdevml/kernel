/*
 * PS/2 keyboard driver, polled.
 *
 * The kernel has no IDT yet, so IRQ1 cannot be serviced. Instead we spin on the
 * controller's status port and pull scancodes out of the output buffer as they
 * appear. Scancode set 1 is what the controller hands us by default: a press
 * sends the code, a release sends the same code with bit 7 set.
 */

#include "keyboard.h"
#include "vga.h"
#include "io.h"

#include <stdbool.h>
#include <stdint.h>

#define PS2_DATA        0x60
#define PS2_STATUS      0x64
#define PS2_OUTPUT_FULL 0x01
#define PS2_FROM_MOUSE  0x20

#define SC_LSHIFT       0x2A
#define SC_RSHIFT       0x36
#define SC_CAPSLOCK     0x3A
#define SC_EXTENDED     0xE0
#define SC_RELEASE      0x80

static const char scancode_plain[128] = {
    /* 0x00 */ 0,    27,   '1',  '2',  '3',  '4',  '5',  '6',
    /* 0x08 */ '7',  '8',  '9',  '0',  '-',  '=',  '\b', '\t',
    /* 0x10 */ 'q',  'w',  'e',  'r',  't',  'y',  'u',  'i',
    /* 0x18 */ 'o',  'p',  '[',  ']',  '\n', 0,    'a',  's',
    /* 0x20 */ 'd',  'f',  'g',  'h',  'j',  'k',  'l',  ';',
    /* 0x28 */ '\'', '`',  0,    '\\', 'z',  'x',  'c',  'v',
    /* 0x30 */ 'b',  'n',  'm',  ',',  '.',  '/',  0,    '*',
    /* 0x38 */ 0,    ' ',  0,    0,    0,    0,    0,    0,
};

static const char scancode_shift[128] = {
    /* 0x00 */ 0,    27,   '!',  '@',  '#',  '$',  '%',  '^',
    /* 0x08 */ '&',  '*',  '(',  ')',  '_',  '+',  '\b', '\t',
    /* 0x10 */ 'Q',  'W',  'E',  'R',  'T',  'Y',  'U',  'I',
    /* 0x18 */ 'O',  'P',  '{',  '}',  '\n', 0,    'A',  'S',
    /* 0x20 */ 'D',  'F',  'G',  'H',  'J',  'K',  'L',  ':',
    /* 0x28 */ '"',  '~',  0,    '|',  'Z',  'X',  'C',  'V',
    /* 0x30 */ 'B',  'N',  'M',  '<',  '>',  '?',  0,    '*',
    /* 0x38 */ 0,    ' ',  0,    0,    0,    0,    0,    0,
};

static bool shift_held;
static bool caps_lock;

static uint8_t read_scancode(void)
{
    for (;;) {
        uint8_t status = inb(PS2_STATUS);

        if ((status & PS2_OUTPUT_FULL) == 0) {
            continue;
        }
        if (status & PS2_FROM_MOUSE) {  /* not ours, drop it */
            (void)inb(PS2_DATA);
            continue;
        }

        return inb(PS2_DATA);
    }
}

char keyboard_getchar(void)
{
    for (;;) {
        uint8_t code = read_scancode();

        if (code == SC_EXTENDED) {      /* arrows and friends, ignored for now */
            (void)read_scancode();
            continue;
        }

        if (code & SC_RELEASE) {
            uint8_t released = code & ~SC_RELEASE;
            if (released == SC_LSHIFT || released == SC_RSHIFT) {
                shift_held = false;
            }
            continue;
        }

        if (code == SC_LSHIFT || code == SC_RSHIFT) {
            shift_held = true;
            continue;
        }

        if (code == SC_CAPSLOCK) {
            caps_lock = !caps_lock;
            continue;
        }

        char c = shift_held ? scancode_shift[code] : scancode_plain[code];

        /* caps lock only affects letters, and it inverts whatever shift did */
        if (caps_lock) {
            if (c >= 'a' && c <= 'z') {
                c = (char)(c - 'a' + 'A');
            } else if (c >= 'A' && c <= 'Z') {
                c = (char)(c - 'A' + 'a');
            }
        }

        if (c != 0) {
            return c;
        }
    }
}

size_t keyboard_read_line(char *buf, size_t size)
{
    size_t length = 0;

    for (;;) {
        char c = keyboard_getchar();

        if (c == '\n') {
            buf[length] = '\0';
            vga_putchar('\n');
            return length;
        }

        if (c == '\b') {
            if (length > 0) {
                length--;
                vga_putchar('\b');
            }
            continue;
        }

        if (c == 27) {              /* escape clears the line */
            while (length > 0) {
                length--;
                vga_putchar('\b');
            }
            continue;
        }

        if (length + 1 < size) {
            buf[length++] = c;
            vga_putchar(c);
        }
    }
}
