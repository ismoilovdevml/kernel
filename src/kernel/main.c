/*
 * The kernel proper.
 *
 * Entered from entry.asm in 32-bit protected mode with a flat address space,
 * a stack, and a zeroed .bss. There is no BIOS left to call, so every service
 * this shell offers talks to the hardware directly.
 */

#include "boot_info.h"
#include "io.h"
#include "keyboard.h"
#include "string.h"
#include "vga.h"

#include <stdbool.h>
#include <stdint.h>

#define CMDLINE_MAX 128

extern char __kernel_end[];

static char cmdline[CMDLINE_MAX];

static inline void cpuid(uint32_t leaf, uint32_t *eax, uint32_t *ebx,
                         uint32_t *ecx, uint32_t *edx)
{
    __asm__ volatile ("cpuid"
                      : "=a"(*eax), "=b"(*ebx), "=c"(*ecx), "=d"(*edx)
                      : "a"(leaf));
}

static const char *e820_type_name(uint32_t type)
{
    switch (type) {
    case E820_USABLE:            return "Usable";
    case E820_RESERVED:          return "Reserved";
    case E820_ACPI_RECLAIMABLE:  return "ACPI reclaimable";
    case E820_ACPI_NVS:          return "ACPI NVS";
    case E820_BAD:               return "Bad memory";
    default:                     return "Unknown";
    }
}

static uint64_t usable_memory_bytes(void)
{
    const e820_entry_t *map = boot_memmap();
    uint16_t count = boot_memmap_count();
    uint64_t total = 0;

    for (uint16_t i = 0; i < count; i++) {
        if (map[i].type == E820_USABLE) {
            total += map[i].length;
        }
    }

    return total;
}


/*
 * Commands
 */

static void cmd_help(void)
{
    vga_puts("Available commands:\n"
             "  help          show this help\n"
             "  clear         clear the screen\n"
             "  about         information about this kernel\n"
             "  echo <text>   print the given text\n"
             "  mem           usable memory according to the BIOS\n"
             "  memmap        the full BIOS memory map\n"
             "  cpuid         what the CPU says about itself\n"
             "  drive         the drive the kernel was booted from\n"
             "  colors        the 16 text mode colors\n"
             "  reboot        restart the machine\n"
             "  halt          stop the CPU\n");
}

static void cmd_about(void)
{
    vga_puts("NanoByte OS kernel, written in C.\n"
             "Loaded from a FAT12 floppy by a two stage bootloader, running in\n"
             "32-bit protected mode with a flat address space.\n"
             "Kernel image ends at 0x");
    vga_put_hex32((uint32_t)__kernel_end);
    vga_puts(".\n");
}

static void cmd_mem(void)
{
    uint64_t bytes = usable_memory_bytes();

    vga_puts("Usable memory: ");
    vga_put_dec((uint32_t)(bytes >> 20));
    vga_puts(" MiB (");
    vga_put_dec((uint32_t)(bytes >> 10));
    vga_puts(" KiB) across ");
    vga_put_dec(boot_memmap_count());
    vga_puts(" regions\n");
}

static void cmd_memmap(void)
{
    const e820_entry_t *map = boot_memmap();
    uint16_t count = boot_memmap_count();

    if (count == 0) {
        vga_puts("No memory map available - stage 2 did not provide one.\n");
        return;
    }

    vga_puts("BASE             LENGTH           TYPE\n");

    for (uint16_t i = 0; i < count; i++) {
        vga_put_hex64(map[i].base);
        vga_putchar(' ');
        vga_put_hex64(map[i].length);
        vga_putchar(' ');
        vga_puts(e820_type_name(map[i].type));
        vga_putchar('\n');
    }
}

static void cmd_cpuid(void)
{
    uint32_t eax, ebx, ecx, edx;
    char vendor[13];

    cpuid(0, &eax, &ebx, &ecx, &edx);

    memcpy(vendor + 0, &ebx, 4);
    memcpy(vendor + 4, &edx, 4);
    memcpy(vendor + 8, &ecx, 4);
    vendor[12] = '\0';

    vga_puts("Vendor: ");
    vga_puts(vendor);
    vga_puts("\nHighest CPUID leaf: ");
    vga_put_dec(eax);
    vga_putchar('\n');

    /* the brand string lives in three extended leaves, when they exist */
    uint32_t max_extended;
    cpuid(0x80000000, &max_extended, &ebx, &ecx, &edx);

    if (max_extended >= 0x80000004) {
        char brand[49];

        for (int i = 0; i < 3; i++) {
            cpuid(0x80000002 + (uint32_t)i, &eax, &ebx, &ecx, &edx);
            memcpy(brand + i * 16 + 0,  &eax, 4);
            memcpy(brand + i * 16 + 4,  &ebx, 4);
            memcpy(brand + i * 16 + 8,  &ecx, 4);
            memcpy(brand + i * 16 + 12, &edx, 4);
        }
        brand[48] = '\0';

        vga_puts("Model:  ");
        vga_puts(brand);
        vga_putchar('\n');
    }

    cpuid(1, &eax, &ebx, &ecx, &edx);
    vga_puts("Features: ");
    if (edx & (1u << 0))  vga_puts("fpu ");
    if (edx & (1u << 4))  vga_puts("tsc ");
    if (edx & (1u << 5))  vga_puts("msr ");
    if (edx & (1u << 6))  vga_puts("pae ");
    if (edx & (1u << 9))  vga_puts("apic ");
    if (edx & (1u << 23)) vga_puts("mmx ");
    if (edx & (1u << 25)) vga_puts("sse ");
    if (edx & (1u << 26)) vga_puts("sse2 ");
    if (ecx & (1u << 0))  vga_puts("sse3 ");
    vga_putchar('\n');
}

static void cmd_drive(void)
{
    uint16_t drive = boot_drive();

    vga_puts("Boot drive: 0x");
    vga_put_hex32(drive);
    vga_puts(drive & 0x80 ? " (hard disk)\n" : " (floppy)\n");
}

static void cmd_colors(void)
{
    static const char *names[16] = {
        "black", "blue", "green", "cyan",
        "red", "magenta", "brown", "light grey",
        "dark grey", "light blue", "light green", "light cyan",
        "light red", "light magenta", "yellow", "white",
    };

    for (int i = 0; i < 16; i++) {
        vga_set_color((enum vga_color)i, VGA_BLACK);
        vga_put_dec_padded((uint32_t)i, 3);
        vga_putchar(' ');
        vga_puts(names[i]);
        vga_putchar('\n');
    }

    vga_set_color(VGA_LIGHT_GREY, VGA_BLACK);
}

static void cmd_reboot(void)
{
    vga_puts("Rebooting...\n");

    /* pulse the CPU reset line through the keyboard controller, the usual
       trick now that there is no BIOS to ask */
    while (inb(0x64) & 0x02) {
        io_wait();
    }
    outb(0x64, 0xFE);

    halt_forever();
}

static void cmd_halt(void)
{
    vga_puts("System halted.\n");
    halt_forever();
}

static void cmd_unknown(const char *line)
{
    vga_puts("Unknown command: \"");
    vga_puts(line);
    vga_puts("\". Type \"help\".\n");
}


/*
 * Shell
 */

static void execute(char *line)
{
    if (line[0] == '\0') {
        return;
    }

    if (strncmp(line, "echo ", 5) == 0) {
        vga_puts(line + 5);
        vga_putchar('\n');
    } else if (strcmp(line, "help") == 0) {
        cmd_help();
    } else if (strcmp(line, "clear") == 0) {
        vga_clear();
    } else if (strcmp(line, "about") == 0) {
        cmd_about();
    } else if (strcmp(line, "mem") == 0) {
        cmd_mem();
    } else if (strcmp(line, "memmap") == 0) {
        cmd_memmap();
    } else if (strcmp(line, "cpuid") == 0) {
        cmd_cpuid();
    } else if (strcmp(line, "drive") == 0) {
        cmd_drive();
    } else if (strcmp(line, "colors") == 0) {
        cmd_colors();
    } else if (strcmp(line, "reboot") == 0) {
        cmd_reboot();
    } else if (strcmp(line, "halt") == 0) {
        cmd_halt();
    } else {
        cmd_unknown(line);
    }
}

static void banner(void)
{
    vga_set_color(VGA_LIGHT_CYAN, VGA_BLACK);
    vga_puts("=============================================\n"
             "  NanoByte OS - 32-bit protected mode kernel\n"
             "  Type \"help\" for the list of commands.\n"
             "=============================================\n\n");
    vga_set_color(VGA_LIGHT_GREY, VGA_BLACK);
}

void kmain(void)
{
    vga_init();
    banner();

    for (;;) {
        vga_set_color(VGA_LIGHT_GREEN, VGA_BLACK);
        vga_puts("kernel> ");
        vga_set_color(VGA_LIGHT_GREY, VGA_BLACK);

        keyboard_read_line(cmdline, sizeof(cmdline));
        execute(cmdline);
    }
}
