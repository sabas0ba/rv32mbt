# rv32mbt

[![CI](https://github.com/sabas0ba/rv32mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/sabas0ba/rv32mbt/actions/workflows/ci.yml)

An RV32IMAC emulator written in MoonBit. It implements a
QEMU-virt-compatible memory map (16550 UART, CLINT, PLIC, sifive_test)
and runs both as a native CLI and as a browser frontend built with the
js backend.

**It boots nommu Linux 6.12 (`CONFIG_RISCV_M_MODE`) to an interactive
busybox shell.** From that shell you can run ordinary userspace
programs linked against musl — and you can run **the emulator itself
inside the guest**:

```
/ # /opt/nested/wasmrun /opt/nested/rv32mbt.wasm /opt/nested/hello.elf 2 2000000
hello from rv32mbt
[wasmrun] guest halted, exit=0, steps=104
```

That is rv32mbt → Linux → wasmrun → rv32mbt (wasm) → `hello.elf`, and
the inner emulator's output is checked against the same expected-output
file as the outer one.

Try it in a browser at
[sabas0ba.github.io/rv32mbt](https://sabas0ba.github.io/rv32mbt/).

## Documentation

| Document | Contents |
|---|---|
| [docs/design.md](docs/design.md) | Architecture, target specification, memory map, verification strategy |
| [docs/linux.md](docs/linux.md) | Booting Linux: kernel build, userspace, `/opt/examples`, `/opt/nested` |
| [docs/toolchain.md](docs/toolchain.md) | Pinned toolchain and dependency versions, and how to update them |
| [docs/releasing.md](docs/releasing.md) | Where the version lives and how a release is cut |
| [CHANGELOG.md](CHANGELOG.md) | Release history |

## Getting started

The toolchain is pinned by the `Dockerfile` at the repository root (see
[docs/toolchain.md](docs/toolchain.md)). It works with podman and
docker alike, and the VS Code devcontainer (`.devcontainer/`) uses the
same image.

```
podman build -t rv32mbt-dev .
podman run --rm -v "$PWD:/work" rv32mbt-dev bash ci/run.sh
```

`ci/run.sh` runs the full regression:

1. version consistency between `moon.mod` and `core/version.mbt`
2. `moon check`
3. `moon test --target native` — core unit tests
4. `moon test --target wasm-gc -p .../wasm` — wasm API tests
5. `moon build --target native --release cmd/main` — the CLI binary
6. fetch, build and run riscv-tests (61 tests)
7. build and run the sample programs, comparing against expected output
8. the Linux boot regression (`RUN_LINUX_BOOT`), covering the
   interactive shell, the userspace samples, the nested emulator,
   `reboot` and `poweroff`
9. `moon build --target js --release web` — the browser module

## Using the CLI

```
moon build --target native --release cmd/main
_build/native/release/build/cmd/main/main.exe [options] <image>

# for example
_build/native/release/build/cmd/main/main.exe tests/build/hello.elf
_build/native/release/build/cmd/main/main.exe tests/build/lifegame.elf
```

An ELF32 (RV32) executable is loaded into DRAM at `0x80000000` and
executed. UART output goes to stdout.

| Option | Meaning |
|---|---|
| `--quiet` | suppress the `[rv32mbt] halted, ...` line printed on exit |
| `--max-steps N` | stop after N instructions (default: unlimited) |
| `--bin` | load the image as a flat binary rather than as ELF |
| `--load-addr A` | load address used with `--bin` |
| `--pc A` | initial program counter |
| `--dtb FILE` | load a DTB near the top of DRAM and set the Linux boot registers |
| `--trace` | write a spike-style commit log to stderr |
| `--version` | print the version and exit |

The emulator stops on the guest's sifive_test finisher (a PASS/FAIL
write) and on the riscv-tests HTIF `tohost` protocol, and reflects the
result in its own exit status — 0 on success, the guest's code on
failure. The test harnesses under `tests/` use the same mechanism. A
program that never halts will run forever, so `--max-steps` is worth
passing when running something by hand.

### Terminal handling

When stdin is a terminal it is put into raw mode — `ICANON` and `ECHO`
are cleared, and so are `ISIG` and `IXON` — and fed to UART0's RX. That
keeps Ctrl-C and Ctrl-S from being intercepted by the host tty so they
reach the guest's line discipline instead. The emulator itself is
driven by the same Ctrl-A escape QEMU uses:

| Key | Action |
|---|---|
| `Ctrl-A` `x` | quit the emulator (the terminal is restored) |
| `Ctrl-A` `a` | send a literal Ctrl-A to the guest |

When input comes from a pipe or a file no escape processing happens and
every byte is passed through unchanged.

### Execution traces

`--trace` follows spike's commit log format and is written to stderr,
separate from the UART output on stdout:

```
core   0: 3 0x80000000 (0x10000537) x10 0x10000000
```

Register writebacks are detected by comparing the register file before
and after each instruction, so writes that do not change a value are
not shown. Memory operands are not recorded.

## Booting Linux

nommu Linux 6.12 with a busybox userspace boots to an interactive
shell, complete with musl-linked sample programs and the nested
emulator. The full walkthrough — kernel build, userspace layout,
`/opt/examples`, `/opt/nested`, power control — is in
[docs/linux.md](docs/linux.md).

## Browser frontend (`web/`)

The emulator built with the js backend, running in the browser. The
default sample is the Linux kernel boot (`vmlinux` + DTB); the other
sample ELFs (hello, hello_c, fib, lifegame, mandelbrot, primes) and
arbitrary ELF or flat binaries can be selected too. The Linux sample
reaches the interactive shell, so `/opt/examples` and the nested
emulator in `/opt/nested` can be tried from the browser as well —
`wasmrun` runs inside the emulated Linux, so no extra runtime is needed
on the browser side. To see the Linux sample locally, build the kernel
with `linux/build.sh` first; without it the other samples still work.

The debug panel offers:

- Run / Pause / Step / Reset, and an execution-speed selector
  (1 inst/s up to full speed)
- the registers (x0–x31 and pc) and the main CSRs (mstatus, mie, mip,
  mtvec, mepc, mcause, mtval, …, plus cycle and instret)
- a memory dump (hex + ASCII, with address entry and jumps to PC / SP)
- an execution trace in spike commit log format, toggleable
- terminal input that works with mobile software keyboards and IMEs
  (tap to start typing); Esc, Tab, the arrow keys, `^C` and `^D` have
  dedicated soft keys

```
bash ci/build_site.sh                       # assemble into _build/site/
python3 -m http.server 8000 -d _build/site  # preview locally
```

The `main` branch is published to
[GitHub Pages](https://sabas0ba.github.io/rv32mbt/).

## wasm module (`wasm/`)

The core VM built with the wasm-gc backend. Every export takes and
returns `Int`, so any wasm host can drive it without marshalling GC
types — images are staged one byte at a time and UART output is read
back the same way. Stepping, reading registers, CSRs and memory, and
collecting execution traces are all supported. CI publishes it as the
`rv32mbt-vm-wasm` artifact.

```
moon build --target wasm-gc --release wasm
# -> _build/wasm-gc/release/build/wasm/wasm.wasm
```

## Tests

- `moon test --target native` — core unit tests
- `tests/fetch_vendor.sh` — fetch the riscv-tests sources (pinned by
  commit SHA, verified by sha256)
- `tests/build_tests.sh` — build them with clang + lld (no RISC-V GNU
  toolchain needed)
- `tests/run_tests.sh <emulator>` — run all 61 and tally pass/fail
- `tests/examples/` — sample programs that write to the UART: hello
  (assembly and C), fib, Conway's Game of Life, mandelbrot
  (fixed-point ASCII rendering) and primes (sieve of Eratosthenes),
  built for bare metal with a small C runtime (`crt0.S` + `rt.c`).
  `run_examples.sh <emulator>` compares their output against the
  `.expect` files in the repository. `build_linux.sh` builds the same
  sources against musl for Linux userspace and installs them into the
  initramfs as `/opt/examples`; the output is byte-for-byte identical,
  so the same `.expect` files apply.
- `tools/wasmrun/` — a small interpreter for an integer-only subset of
  wasm (no floating point; 72 instructions plus `memory.copy`/`fill`).
  It exists to run the emulator's wasm module inside the guest;
  `CC_HOST=1 bash tools/wasmrun/build.sh` builds a host version.
- `ci/test_linux_boot.sh` — the Linux boot regression. It boots the
  kernel and drives the interactive shell through `uname`, each
  `/opt/examples` sample (output checked against the `.expect` files
  via md5sum), the nested emulator in `/opt/nested`, `reboot`
  (including the re-boot after the warm reset) and `poweroff`,
  checking for the expected markers and a clean exit. `ci/run.sh`
  selects it with `RUN_LINUX_BOOT` (auto / 1 / 0; auto — the default —
  runs it only when the kernel artifacts exist). CI caches the
  artifacts with actions/cache and always runs it.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs `ci/run.sh` in the
image above for every push and pull request, and publishes the
`ci/build_dist.sh` output — the native CLI, the wasm VM module and the
web site — as artifacts. Pushes to `main` additionally deploy the site
assembled by `ci/build_site.sh` to GitHub Pages (the Pages source must
be set to "GitHub Actions").

`.github/workflows/release.yml` builds the same artifacts for a `v*`
tag and attaches them to the corresponding GitHub Release; see
[docs/releasing.md](docs/releasing.md).

## Licence and attribution

- This project: Apache-2.0 (see [LICENSE](LICENSE))
- riscv-tests / riscv-test-env: BSD-3-Clause (see
  [tests/VENDOR-MANIFEST.md](tests/VENDOR-MANIFEST.md))
- The QEMU virt memory map is referenced only for its address constants,
  as a published specification
- Linux kernel: GPL-2.0. The sources are not part of this repository
  and are fetched from kernel.org at build time. The
  corresponding-source statement for the distributed `vmlinux` is in
  [linux/README.md](linux/README.md).
