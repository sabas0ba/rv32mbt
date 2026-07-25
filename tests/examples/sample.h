/* Minimal bare-metal I/O helpers for the C examples. Talks directly to
 * the 16550 UART at 0x1000_0000 (QEMU virt / rv32mbt memory map). */
#ifndef SAMPLE_H
#define SAMPLE_H

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

#endif /* SAMPLE_H */
