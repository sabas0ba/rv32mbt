/* Run the rv32mbt emulator core — as a WebAssembly module — on the
 * small interpreter in wasm.c, and boot a RISC-V program inside it.
 *
 * Built for the host it makes a handy check of the wasm module; built
 * for riscv32-linux-musl and dropped into the initramfs, it lets the
 * emulated Linux guest run the very emulator it is running on:
 *
 *   rv32mbt -> Linux -> wasmrun -> rv32mbt (wasm) -> guest program
 *
 * Usage: wasmrun <module.wasm> <program.elf> [ram_mb] [max_steps]
 */
#include "wasm.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint8_t *read_file(const char *path, size_t *size) {
  FILE *f = fopen(path, "rb");
  if (!f)
    return NULL;
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  if (n < 0) {
    fclose(f);
    return NULL;
  }
  uint8_t *buf = malloc((size_t)n ? (size_t)n : 1);
  if (buf && fread(buf, 1, (size_t)n, f) != (size_t)n) {
    free(buf);
    buf = NULL;
  }
  fclose(f);
  *size = (size_t)n;
  return buf;
}

/* Call an export by name with `nargs` Int arguments. */
static int call_i(WasmModule *m, const char *name, const uint64_t *args,
                  uint32_t nargs, uint64_t *out) {
  int idx = wasm_export(m, name);
  if (idx < 0) {
    fprintf(stderr, "wasmrun: module has no export '%s'\n", name);
    return -1;
  }
  uint64_t res[4];
  int n = wasm_call(m, (uint32_t)idx, args, nargs, res, 4);
  if (n < 0) {
    fprintf(stderr, "wasmrun: %s trapped: %s\n", name,
            m->error ? m->error : "unknown");
    return -1;
  }
  if (out && n > 0)
    *out = res[0];
  return 0;
}

/* Drain the emulated UART into stdout. */
static int drain(WasmModule *m, int take_byte) {
  int wrote = 0;
  for (;;) {
    uint64_t b = 0;
    if (wasm_call(m, (uint32_t)take_byte, NULL, 0, &b, 1) < 0) {
      fprintf(stderr, "wasmrun: vm_take_byte trapped: %s\n",
              m->error ? m->error : "unknown");
      return -1;
    }
    if ((int32_t)(uint32_t)b < 0)
      break;
    putchar((int)(b & 0xFF));
    wrote++;
  }
  if (wrote)
    fflush(stdout);
  return wrote;
}

int main(int argc, char **argv) {
  if (argc < 3) {
    fprintf(stderr,
            "usage: %s <module.wasm> <program.elf> [ram_mb] [max_steps]\n",
            argv[0]);
    return 2;
  }
  uint32_t ram_mb = (argc > 3) ? (uint32_t)strtoul(argv[3], NULL, 0) : 4;
  uint64_t max_steps =
      (argc > 4) ? strtoull(argv[4], NULL, 0) : 200000000ull;

  size_t wsize = 0, esize = 0;
  uint8_t *wbytes = read_file(argv[1], &wsize);
  if (!wbytes) {
    fprintf(stderr, "wasmrun: cannot read %s\n", argv[1]);
    return 1;
  }
  uint8_t *ebytes = read_file(argv[2], &esize);
  if (!ebytes) {
    fprintf(stderr, "wasmrun: cannot read %s\n", argv[2]);
    return 1;
  }

  WasmModule m;
  if (wasm_load(&m, wbytes, wsize) != 0) {
    fprintf(stderr, "wasmrun: cannot load module: %s\n",
            m.error ? m.error : "unknown");
    return 1;
  }

  uint64_t arg = ram_mb;
  if (call_i(&m, "vm_create", &arg, 1, NULL) != 0)
    return 1;
  if (call_i(&m, "vm_stage_clear", NULL, 0, NULL) != 0)
    return 1;

  /* The export surface is Int-only by design, so the image is staged
   * one byte at a time. */
  int stage_push = wasm_export(&m, "vm_stage_push");
  if (stage_push < 0) {
    fprintf(stderr, "wasmrun: module has no export 'vm_stage_push'\n");
    return 1;
  }
  for (size_t i = 0; i < esize; i++) {
    uint64_t b = ebytes[i];
    if (wasm_call(&m, (uint32_t)stage_push, &b, 1, NULL, 0) < 0) {
      fprintf(stderr, "wasmrun: staging trapped at byte %zu: %s\n", i,
              m.error ? m.error : "unknown");
      return 1;
    }
  }

  uint64_t rc = 0;
  if (call_i(&m, "vm_load_elf_staged", NULL, 0, &rc) != 0)
    return 1;
  if ((int32_t)(uint32_t)rc < 0) {
    fprintf(stderr, "wasmrun: the module rejected the ELF image\n");
    return 1;
  }

  int run = wasm_export(&m, "vm_run");
  int halted = wasm_export(&m, "vm_halted");
  int take_byte = wasm_export(&m, "vm_take_byte");
  int exit_code = wasm_export(&m, "vm_exit_code");
  if (run < 0 || halted < 0 || take_byte < 0 || exit_code < 0) {
    fprintf(stderr, "wasmrun: module is missing the run/halt exports\n");
    return 1;
  }

  uint64_t steps = 0;
  for (;;) {
    uint64_t h = 0;
    if (wasm_call(&m, (uint32_t)halted, NULL, 0, &h, 1) < 0) {
      fprintf(stderr, "wasmrun: vm_halted trapped: %s\n",
              m.error ? m.error : "unknown");
      return 1;
    }
    if (h)
      break;
    if (steps >= max_steps) {
      if (drain(&m, take_byte) < 0)
        return 1;
      fprintf(stderr, "\nwasmrun: step limit reached (%llu)\n",
              (unsigned long long)steps);
      return 1;
    }
    uint64_t batch = 4096;
    uint64_t did = 0;
    if (wasm_call(&m, (uint32_t)run, &batch, 1, &did, 1) < 0) {
      fprintf(stderr, "wasmrun: vm_run trapped: %s\n",
              m.error ? m.error : "unknown");
      return 1;
    }
    steps += (uint32_t)did;
    if (drain(&m, take_byte) < 0)
      return 1;
  }
  if (drain(&m, take_byte) < 0)
    return 1;

  uint64_t code = 0;
  if (call_i(&m, "vm_exit_code", NULL, 0, &code) != 0)
    return 1;
  fprintf(stderr, "[wasmrun] guest halted, exit=%d, steps=%llu\n",
          (int32_t)(uint32_t)code, (unsigned long long)steps);

  wasm_free(&m);
  free(wbytes);
  free(ebytes);
  return (int)(int32_t)(uint32_t)code;
}
