/* Sieve of Eratosthenes up to 1000: print the primes ten per line and
 * the total count (168). Exercises .bss arrays, nested loops and the
 * M extension (decimal printing). */
#include "sample.h"

#define N 1000

static unsigned char composite[N + 1];

int main(void) {
  int count = 0;
  for (int i = 2; i <= N; i++) {
    if (composite[i])
      continue;
    count++;
    uart_putu((unsigned)i);
    uart_putc(count % 10 == 0 ? '\n' : ' ');
    for (int j = i + i; j <= N; j += i)
      composite[j] = 1;
  }
  if (count % 10 != 0)
    uart_putc('\n');
  uart_puts("count=");
  uart_putu((unsigned)count);
  uart_putc('\n');
  return 0;
}
