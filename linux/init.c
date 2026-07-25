/* Interactive PID 1 for rv32mbt: a freestanding mini shell over the
 * console tty (canonical mode: the kernel handles echo and line
 * editing). Static PIE with no relocations — no address-valued
 * globals, no jump tables (-fno-jump-tables) — so the FDPIC loader
 * can place it anywhere without relocation processing.
 *
 * Builtins: help, echo, uname, mem, uptime, poweroff, reboot.
 */

typedef unsigned int u32;
typedef unsigned short u16;

#define NR_read 63
#define NR_write 64
#define NR_uname 160
#define NR_sysinfo 179
#define NR_reboot 142

#define REBOOT_MAGIC1 0xfee1dead
#define REBOOT_MAGIC2 0x28121969
#define REBOOT_CMD_POWER_OFF 0x4321fedc
#define REBOOT_CMD_RESTART 0x01234567

static long sys4(long n, long a0, long a1, long a2, long a3) {
  register long ra0 __asm__("a0") = a0;
  register long ra1 __asm__("a1") = a1;
  register long ra2 __asm__("a2") = a2;
  register long ra3 __asm__("a3") = a3;
  register long ra7 __asm__("a7") = n;
  __asm__ volatile("ecall"
                   : "+r"(ra0)
                   : "r"(ra1), "r"(ra2), "r"(ra3), "r"(ra7)
                   : "memory");
  return ra0;
}

static long sys1(long n, long a0) { return sys4(n, a0, 0, 0, 0); }

struct utsname {
  char sysname[65];
  char nodename[65];
  char release[65];
  char version[65];
  char machine[65];
  char domainname[65];
};

struct sysinfo {
  long uptime;
  u32 loads[3];
  u32 totalram;
  u32 freeram;
  u32 sharedram;
  u32 bufferram;
  u32 totalswap;
  u32 freeswap;
  u16 procs;
  u16 pad;
  u32 totalhigh;
  u32 freehigh;
  u32 mem_unit;
  char reserved[8];
};

static u32 str_len(const char *s) {
  u32 n = 0;
  while (s[n])
    n++;
  return n;
}

static void put(const char *s) { sys4(NR_write, 1, (long)s, str_len(s), 0); }

static void put_u32(u32 v) {
  char buf[10];
  int n = 0;
  do {
    buf[n++] = (char)('0' + v % 10u);
    v /= 10u;
  } while (v);
  while (n) {
    char c = buf[--n];
    sys4(NR_write, 1, (long)&c, 1, 0);
  }
}

static int str_eq(const char *a, const char *b) {
  while (*a && *a == *b) {
    a++;
    b++;
  }
  return *a == *b;
}

static void cmd_uname(void) {
  struct utsname u;
  sys1(NR_uname, (long)&u);
  put(u.sysname);
  put(" ");
  put(u.release);
  put(" ");
  put(u.version);
  put(" ");
  put(u.machine);
  put("\n");
}

static void cmd_mem(void) {
  struct sysinfo si;
  sys1(NR_sysinfo, (long)&si);
  /* mem_unit is 1 on this configuration; sizes fit in 32 bits */
  put("total ");
  put_u32(si.totalram / 1024u * si.mem_unit);
  put(" KiB, free ");
  put_u32(si.freeram / 1024u * si.mem_unit);
  put(" KiB, procs ");
  put_u32(si.procs);
  put("\n");
}

static void cmd_uptime(void) {
  struct sysinfo si;
  sys1(NR_sysinfo, (long)&si);
  put_u32((u32)si.uptime);
  put(" s\n");
}

static void do_reboot(u32 cmd) {
  sys4(NR_reboot, (long)REBOOT_MAGIC1, (long)REBOOT_MAGIC2, (long)cmd, 0);
}

static void cmd_help(void) {
  put("builtins: help echo <text> uname mem uptime poweroff reboot\n");
}

int main(void) {
  put("\nrv32mbt mini shell (PID 1). Type 'help'.\n");
  char line[256];
  for (;;) {
    put("rv32mbt# ");
    long n = sys4(NR_read, 0, (long)line, sizeof(line) - 1, 0);
    if (n <= 0)
      continue;
    /* strip the trailing newline */
    if (line[n - 1] == '\n')
      n--;
    line[n] = 0;
    if (n == 0)
      continue;
    if (str_eq(line, "help")) {
      cmd_help();
    } else if (line[0] == 'e' && line[1] == 'c' && line[2] == 'h' &&
               line[3] == 'o' && (line[4] == ' ' || line[4] == 0)) {
      put(line[4] == ' ' ? line + 5 : "");
      put("\n");
    } else if (str_eq(line, "uname")) {
      cmd_uname();
    } else if (str_eq(line, "mem")) {
      cmd_mem();
    } else if (str_eq(line, "uptime")) {
      cmd_uptime();
    } else if (str_eq(line, "poweroff")) {
      put("powering off\n");
      do_reboot(REBOOT_CMD_POWER_OFF);
    } else if (str_eq(line, "reboot")) {
      do_reboot(REBOOT_CMD_RESTART);
    } else {
      put(line);
      put(": not found (try 'help')\n");
    }
  }
}

void _start(void) {
  main();
  do_reboot(REBOOT_CMD_POWER_OFF);
  for (;;)
    ;
}
