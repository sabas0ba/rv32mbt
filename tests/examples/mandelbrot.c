/* ASCII Mandelbrot set, 76x24, Q10 fixed point (32-bit arithmetic
 * only). Exercises the M extension heavily via the fixed-point
 * multiplies in the inner loop. */
#include "sample.h"

#define SH 10
#define ONE (1 << SH)
#define MAX_ITER 48

int main(void) {
  static const char pal[11] = " .:-=+*#%@";
  for (int py = 0; py < 24; py++) {
    for (int px = 0; px < 76; px++) {
      /* c spans re in [-2.2, 0.8], im in [-1.2, 1.2] */
      int cr = -2253 + px * 41;
      int ci = -1229 + py * 107;
      int zr = 0, zi = 0;
      int i = 0;
      while (i < MAX_ITER) {
        int zr2 = (zr * zr) >> SH;
        int zi2 = (zi * zi) >> SH;
        if (zr2 + zi2 > (4 << SH))
          break;
        int t = zr2 - zi2 + cr;
        zi = ((zr * zi) >> (SH - 1)) + ci;
        zr = t;
        i++;
      }
      uart_putc(pal[(i * 9) / MAX_ITER]);
    }
    uart_putc('\n');
  }
  return 0;
}
