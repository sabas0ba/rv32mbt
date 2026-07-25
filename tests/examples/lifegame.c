/* Conway's Game of Life on a 16x8 torus. Starts from a glider and
 * prints every generation; the pattern shifts one cell right and down
 * every four generations, so the output is easy to eyeball and fully
 * deterministic. Exercises global arrays (.bss), nested loops and the
 * M extension (remainder for wrap-around). */
#include "sample.h"

#define W 16
#define H 8
#define GENERATIONS 8

static unsigned char buf_a[H][W];
static unsigned char buf_b[H][W];
static unsigned char (*grid)[W] = buf_a;
static unsigned char (*next)[W] = buf_b;

static void print_grid(unsigned gen) {
  uart_puts("gen ");
  uart_putu(gen);
  uart_putc('\n');
  for (int y = 0; y < H; y++) {
    for (int x = 0; x < W; x++)
      uart_putc(grid[y][x] ? '#' : '.');
    uart_putc('\n');
  }
}

static int neighbors(int y, int x) {
  int n = 0;
  for (int dy = -1; dy <= 1; dy++)
    for (int dx = -1; dx <= 1; dx++) {
      if (dy == 0 && dx == 0)
        continue;
      int yy = (y + dy + H) % H;
      int xx = (x + dx + W) % W;
      n += grid[yy][xx];
    }
  return n;
}

int main(void) {
  /* Glider heading south-east. */
  grid[0][1] = 1;
  grid[1][2] = 1;
  grid[2][0] = 1;
  grid[2][1] = 1;
  grid[2][2] = 1;

  for (unsigned gen = 0; gen <= GENERATIONS; gen++) {
    print_grid(gen);
    for (int y = 0; y < H; y++)
      for (int x = 0; x < W; x++) {
        int n = neighbors(y, x);
        next[y][x] = (unsigned char)(n == 3 || (n == 2 && grid[y][x]));
      }
    unsigned char (*t)[W] = grid;
    grid = next;
    next = t;
  }
  return 0;
}
