/* Print a greeting via the UART and exit through the finisher. */
#include "sample.h"

int main(void) {
  uart_puts("hello from C on rv32mbt\n");
  return 0;
}
