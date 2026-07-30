#ifndef KEYBOARD_H
#define KEYBOARD_H

#include <stddef.h>

/* Blocks until a key that produces a character is pressed. */
char keyboard_getchar(void);

/* Reads a line into buf (at most size - 1 characters plus a terminator),
   echoing it and handling backspace. Returns the length. */
size_t keyboard_read_line(char *buf, size_t size);

#endif
