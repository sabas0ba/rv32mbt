# Design

rv32mbt is an RV32 emulator written in MoonBit. It boots nommu Linux
(`CONFIG_RISCV_M_MODE`), runs a practical userspace on top of it, and
can run the emulator itself inside the guest. It targets both native
execution (native backend) and the browser (js backend).

## Target specification

- ISA: RV32IMAC with Zicsr and Zifencei
- Privilege levels: M-mode and U-mode. nommu Linux built with
  `CONFIG_RISCV_M_MODE` runs the kernel in M-mode and userspace in
  U-mode, so S-mode, the MMU and PMP are deliberately not implemented.
- Harts: 1
- Endianness: little

## Memory map (QEMU virt compatible)

Source: `virt_memmap[]` in `hw/riscv/virt.c` and
`include/hw/riscv/virt.h` of QEMU v8.2.2.

| Region | Base | Size | Notes |
|---|---|---|---|
| TEST (sifive_test) | 0x0010_0000 | 0x1000 | finisher device; used by riscv-tests and by poweroff |
| CLINT | 0x0200_0000 | 0x1_0000 | msip@0x0, mtimecmp@0x4000, mtime@0xBFF8 |
| PLIC | 0x0C00_0000 | 0x60_0000 | priority@0x0, pending@0x1000, enable@0x2000 (+0x80/ctx), threshold/claim@0x20_0000 (+0x1000/ctx) |
| UART0 | 0x1000_0000 | 0x100 | 16550A, regshift=0, IRQ=10, clock 3.6864 MHz |
| DRAM | 0x8000_0000 | variable (128 MiB by default) | |

- timebase: 10 MHz (`RISCV_ACLINT_DEFAULT_TIMEBASE_FREQ`)
- UART0_IRQ = 10 (PLIC source number)

## Architecture

```
core/                 backend-independent emulator
  types.mbt           shared types: traps, step results
  machine.mbt         memory map, SoC assembly, execution loop, warm reset
  exec.mbt            instruction decode and execution (I / M / A / Zicsr)
  rvc.mbt             RVC expansion to the 32-bit encodings
  csr.mbt             CSR file (M-mode)
  ram.mbt             DRAM (FixedArray[Byte])
  uart.mbt            16550A model (I/O injected as callbacks)
  clint.mbt           CLINT
  plic.mbt            PLIC
  elf.mbt             minimal ELF32 loader
  trace.mbt           spike-style commit log
  version.mbt         the project version reported by the binaries
cmd/main/             native backend CLI (ELF / flat binary loading, UART <-> stdio)
web/                  js backend + browser page (UART <-> DOM)
wasm/                 wasm-gc module with an Int-only export surface
tools/wasmrun/        small wasm interpreter, for running the core in the guest
linux/                nommu Linux kernel and busybox userspace build
tests/                riscv-tests runner, bare-metal samples
```

### Design decisions

- The core performs no I/O of its own. UART TX and RX are injected as
  callbacks (`(Byte) -> Unit` and `() -> Int`), which is what lets the
  same code serve the native, js and wasm frontends.
- Memory is a flat `FixedArray[Byte]`. Loads and stores compose values
  little-endian.
- Execution is a functional fetch-decode-execute loop. Decoding
  produces an enum and execution dispatches on it with `match`.
- Traps are represented as a return value (`StepResult`) rather than as
  a MoonBit exception.
- CSRs implemented: mstatus, misa, mie, mip, mtvec, mscratch, mepc,
  mcause, mtval, mhartid, mcycle(h), minstret(h), mvendorid, marchid,
  mimpid and others. The `time` CSR is not provided as a separate
  counter; `rdtime` returns the CLINT's mtime.
- A write of `0x7777` to the sifive_test finisher performs a warm reset:
  RAM is cleared, the boot images are replayed, and the devices and CSRs
  are reinitialised. This is what makes `reboot` work in the guest.

### Running the emulator inside itself

The emulator core is also built for the linear-memory wasm target and
shipped in the guest's initramfs together with `wasmrun`
(`tools/wasmrun/`), a small integer-only wasm interpreter. The nesting
is rv32mbt → Linux → wasmrun → rv32mbt (wasm) → guest program.

The wasm hop exists because MoonBit cannot currently be built for
riscv32: `moonc` only accepts 64-bit explicit targets and its native
runtime is not distributed. The browser's wasm-gc build is a separate
one — it needs a GC-aware host, which a small interpreter is not.

## Capabilities and how they are verified

| Capability | Verified by |
|---|---|
| RV32IM + Zicsr, M-mode traps, 16550 UART | riscv-tests rv32ui / rv32um, unit tests |
| A extension (LR/SC, AMO), Zifencei | riscv-tests rv32ua |
| C extension (RVC) | riscv-tests rv32uc, booting a C-enabled kernel |
| CLINT (mtime / mtimecmp / msip) and PLIC | interrupt unit tests |
| nommu Linux boot (DTB supply, boot protocol) | kernel boot log in `ci/test_linux_boot.sh` |
| U-mode userspace (initramfs, binfmt_elf_fdpic) | interactive init in `ci/test_linux_boot.sh` |
| busybox userspace (init/inittab, devtmpfs, applets) | interactive shell checks in the boot regression |
| Warm reset (sifive_test 0x7777) | unit tests plus `reboot` in the boot regression |
| musl-linked userspace programs | the boot regression matches `/opt/examples` against the `.expect` files |
| Self-hosting (the emulator inside the guest) | the boot regression matches `/opt/nested` against `hello.expect` |

### Verification strategy

- riscv-tests (rv32ui-p-\*, rv32um-p-\*, rv32ua-p-\*, rv32uc-p-\*) are
  built with clang + lld and their pass/fail result is read through the
  HTIF `tohost` protocol in CI.
- MoonBit unit tests cover the decoder, ALU, CSRs and the UART
  registers individually.
- The reference toolchain versions are pinned in the Dockerfiles; see
  [toolchain.md](toolchain.md).

## Intellectual property

- No code is ported from other emulators — in particular no GPL code
  from QEMU. Only the address map constants, which are a published
  specification, are taken from QEMU.
- Primary sources for the specification: the RISC-V Unprivileged and
  Privileged ISA specifications, the 16550 UART datasheet-compatible
  specification, and the SiFive CLINT/PLIC specifications.
