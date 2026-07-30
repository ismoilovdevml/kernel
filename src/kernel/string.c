/*
 * The handful of libc functions the kernel needs. There is no C library in a
 * freestanding build, and GCC is allowed to emit calls to memset/memcpy on its
 * own, so these have to exist.
 */

#include "string.h"

#include <stdint.h>

size_t strlen(const char *s)
{
    const char *p = s;
    while (*p) {
        p++;
    }
    return (size_t)(p - s);
}

int strcmp(const char *a, const char *b)
{
    while (*a && *a == *b) {
        a++;
        b++;
    }
    return (int)(unsigned char)*a - (int)(unsigned char)*b;
}

int strncmp(const char *a, const char *b, size_t n)
{
    while (n > 0 && *a && *a == *b) {
        a++;
        b++;
        n--;
    }
    if (n == 0) {
        return 0;
    }
    return (int)(unsigned char)*a - (int)(unsigned char)*b;
}

void *memset(void *dest, int value, size_t count)
{
    uint8_t *p = (uint8_t *)dest;
    while (count--) {
        *p++ = (uint8_t)value;
    }
    return dest;
}

void *memcpy(void *dest, const void *src, size_t count)
{
    uint8_t *d = (uint8_t *)dest;
    const uint8_t *s = (const uint8_t *)src;
    while (count--) {
        *d++ = *s++;
    }
    return dest;
}
