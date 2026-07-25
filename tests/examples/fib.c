/* Print fib(0)..fib(30) iteratively. Exercises 32-bit add/compare and
 * the M extension through the decimal printer. */
#include "sample.h"

int main(void) {
  unsigned a = 0, b = 1;
  for (unsigned i = 0; i <= 30; i++) {
    uart_puts("fib(");
    uart_putu(i);
    uart_puts(")=");
    uart_putu(a);
    uart_putc('\n');
    unsigned next = a + b;
    a = b;
    b = next;
  }
  return 0;
}
