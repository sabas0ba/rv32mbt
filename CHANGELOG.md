# Changelog

All notable changes to this project are recorded here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-07-28

First stable release. The emulator boots nommu Linux to an interactive
shell, runs ordinary musl-linked userspace programs, and can run itself
inside its own guest.

### Emulator core

- RV32IMAC with Zicsr and Zifencei, M-mode and U-mode, single hart.
- QEMU-virt-compatible memory map: 16550A UART, CLINT, PLIC and the
  sifive_test finisher.
- Warm reset on a sifive_test `0x7777` request — RAM is cleared, the
  boot images are replayed and the devices and CSRs are reinitialised —
  which is what makes `reboot` work in the guest.
- Execution traces in spike's commit log format.
- Verified against 61 riscv-tests (rv32ui, rv32um, rv32ua, rv32uc) plus
  MoonBit unit tests for the decoder, CSRs, privilege transitions and
  the UART.

### Frontends

- Native CLI (`cmd/main`): ELF32 and flat binary loading, DTB supply
  and Linux boot registers, raw-mode terminal handling with a QEMU-style
  Ctrl-A escape, and a `--version` flag.
- Browser frontend (`web/`) on the js backend, with a debug panel for
  registers, CSRs, memory and traces, and terminal input that works with
  mobile software keyboards.
- wasm-gc module (`wasm/`) with an Int-only export surface, so any wasm
  host can drive the VM without marshalling GC types.

### Linux target

- nommu Linux 6.12.97 (`CONFIG_RISCV_M_MODE`) boots from a
  reproducible, sha256-pinned build.
- busybox 1.36.1 userspace against musl 1.2.5, static PIE loaded through
  `binfmt_elf_fdpic`, with busybox init as PID 1, devtmpfs and applet
  symlinks. This required porting musl's riscv64 `vfork.s` to riscv32:
  without it musl falls back to `clone(SIGCHLD, 0)`, which on nommu
  produces a child sharing all memory with a parent that was never
  suspended.
- `/opt/examples`: the sample programs linked against musl, producing
  byte-identical output to the bare-metal builds.
- `/opt/nested`: the emulator core as a linear-memory wasm module plus
  `wasmrun` (`tools/wasmrun/`), a small integer-only wasm interpreter,
  so the guest can run the emulator that is running it.
- `poweroff` and `reboot` both work through init.

### Infrastructure

- Pinned toolchain images for the emulator and for the kernel build.
- CI runs the full regression, including the Linux boot test, and
  publishes the CLI, the wasm module and the web site as artifacts.
- The `main` branch is deployed to GitHub Pages.

[1.0.0]: https://github.com/sabas0ba/rv32mbt/releases/tag/v1.0.0
