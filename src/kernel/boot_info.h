#ifndef BOOT_INFO_H
#define BOOT_INFO_H

#include <stdint.h>

/*
 * What stage 2 left behind at a fixed address before it switched to protected
 * mode. int 15h is a real mode BIOS service, so this is the only chance the
 * kernel gets to learn the machine's memory layout.
 */

#define BOOT_INFO_COUNT_ADDR    0x8000
#define BOOT_INFO_DRIVE_ADDR    0x8002
#define BOOT_INFO_ENTRIES_ADDR  0x8004

typedef struct {
    uint64_t base;
    uint64_t length;
    uint32_t type;
    uint32_t acpi_attributes;
} __attribute__((packed)) e820_entry_t;

enum e820_type {
    E820_USABLE          = 1,
    E820_RESERVED        = 2,
    E820_ACPI_RECLAIMABLE = 3,
    E820_ACPI_NVS        = 4,
    E820_BAD             = 5,
};

static inline uint16_t boot_memmap_count(void)
{
    return *(volatile uint16_t *)BOOT_INFO_COUNT_ADDR;
}

static inline uint16_t boot_drive(void)
{
    return *(volatile uint16_t *)BOOT_INFO_DRIVE_ADDR;
}

static inline const e820_entry_t *boot_memmap(void)
{
    return (const e820_entry_t *)BOOT_INFO_ENTRIES_ADDR;
}

#endif
