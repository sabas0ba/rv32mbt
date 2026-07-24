/* Native host stubs for the rv32mbt CLI (POSIX). */
#include <moonbit.h>

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <termios.h>
#include <unistd.h>

/* File size in bytes, or -1 on error. For non-regular files (e.g.
 * /proc/self/cmdline) falls back to reading into a bounded buffer. */
MOONBIT_FFI_EXPORT
int32_t rv_file_size(moonbit_bytes_t path) {
  struct stat st;
  if (stat((const char *)path, &st) != 0) {
    return -1;
  }
  if (S_ISREG(st.st_mode) && st.st_size > 0) {
    return (int32_t)st.st_size;
  }
  /* procfs files report size 0; read to determine the real length */
  int fd = open((const char *)path, O_RDONLY);
  if (fd < 0) {
    return -1;
  }
  static char tmp[65536];
  int32_t total = 0;
  ssize_t n;
  while ((n = read(fd, tmp, sizeof(tmp))) > 0) {
    total += (int32_t)n;
  }
  close(fd);
  return n < 0 ? -1 : total;
}

/* Read the whole file into buf (length = Moonbit_array_length(buf)).
 * Returns the number of bytes read, or -1. */
MOONBIT_FFI_EXPORT
int32_t rv_read_into(moonbit_bytes_t path, moonbit_bytes_t buf) {
  int fd = open((const char *)path, O_RDONLY);
  if (fd < 0) {
    return -1;
  }
  int32_t cap = (int32_t)Moonbit_array_length(buf);
  int32_t total = 0;
  while (total < cap) {
    ssize_t n = read(fd, (char *)buf + total, (size_t)(cap - total));
    if (n < 0) {
      close(fd);
      return -1;
    }
    if (n == 0) {
      break;
    }
    total += (int32_t)n;
  }
  close(fd);
  return total;
}

MOONBIT_FFI_EXPORT
void rv_put_byte(int32_t b) {
  unsigned char c = (unsigned char)(b & 0xFF);
  fwrite(&c, 1, 1, stdout);
  fflush(stdout);
}

/* Non-blocking read of one byte from stdin; -1 if none available. */
MOONBIT_FFI_EXPORT
int32_t rv_get_byte(void) {
  int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
  fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
  unsigned char c;
  ssize_t n = read(STDIN_FILENO, &c, 1);
  fcntl(STDIN_FILENO, F_SETFL, flags);
  return n == 1 ? (int32_t)c : -1;
}

static struct termios rv_saved_termios;
static int rv_termios_saved = 0;

/* enable=1: cbreak mode (no echo, no line buffering) when stdin is a tty.
 * enable=0: restore. */
MOONBIT_FFI_EXPORT
void rv_term_raw(int32_t enable) {
  if (!isatty(STDIN_FILENO)) {
    return;
  }
  if (enable) {
    struct termios t;
    if (tcgetattr(STDIN_FILENO, &t) != 0) {
      return;
    }
    rv_saved_termios = t;
    rv_termios_saved = 1;
    t.c_lflag &= ~(tcflag_t)(ICANON | ECHO);
    t.c_cc[VMIN] = 0;
    t.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSANOW, &t);
  } else if (rv_termios_saved) {
    tcsetattr(STDIN_FILENO, TCSANOW, &rv_saved_termios);
    rv_termios_saved = 0;
  }
}

MOONBIT_FFI_EXPORT
void rv_exit(int32_t code) {
  fflush(stdout);
  exit(code);
}
