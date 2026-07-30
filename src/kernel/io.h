#ifndef IO_H
#define IO_H

#include <stdint.h>

static inline void outb(uint16_t port, uint8_t value)
{
    __asm__ volatile ("outb %0, %1" : : "a"(value), "Nd"(port));
}

static inline uint8_t inb(uint16_t port)
{
    uint8_t value;
    __asm__ volatile ("inb %1, %0" : "=a"(value) : "Nd"(port));
    return value;
}

/* Wastes a few hundred nanoseconds by writing to an unused port. Some old
   controllers need a moment between back to back accesses. */
static inline void io_wait(void)
{
    outb(0x80, 0);
}

static inline void halt_forever(void)
{
    for (;;) {
        __asm__ volatile ("cli; hlt");
    }
}

#endif
