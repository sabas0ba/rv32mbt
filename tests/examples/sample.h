/* I/O helpers shared by the C examples.
 *
 * The same sources build two ways and must produce byte-identical
 * output, so the .expect files cover both:
 *
 *   bare metal (default) — talks straight to the 16550 UART at
 *     0x1000_0000 (QEMU virt / rv32mbt memory map), freestanding.
 *   hosted (__linux__)   — goes through the C library's stdio, i.e.
 *     the Linux guest's write(2), so the examples double as a test
 *     that userspace programs other than busybox run on the guest.
 */
#ifndef SAMPLE_H
#define SAMPLE_H

#ifdef __linux__

#include <stdio.h>

static inline void uart_putc(char c) { putchar(c); }

static inline void uart_puts(const char *s) { fputs(s, stdout); }

/* Print an unsigned integer in decimal. */
static inline void uart_putu(unsigned v) { printf("%u", v); }

#else /* bare metal */

#define UART0_THR (*(volatile unsigned char *)0x10000000u)

static inline void uart_putc(char c) { UART0_THR = (unsigned char)c; }

static inline void uart_puts(const char *s) {
  while (*s)
    uart_putc(*s++);
}

/* Print an unsigned integer in decimal. */
static inline void uart_putu(unsigned v) {
  char buf[10];
  int n = 0;
  do {
    buf[n++] = (char)('0' + v % 10u);
    v /= 10u;
  } while (v);
  while (n)
    uart_putc(buf[--n]);
}

#endif /* __linux__ */

#endif /* SAMPLE_H */
