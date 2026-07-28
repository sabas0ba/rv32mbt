# Booting Linux on rv32mbt

rv32mbt boots a nommu Linux kernel (`CONFIG_RISCV_M_MODE`) with a
busybox userspace and an interactive shell. Everything under `linux/`
builds that target.

The kernel runs in M-mode and userspace in U-mode; there is no MMU, no
S-mode and no PMP, which is why the nommu configuration is the one that
fits. Userspace binaries are static PIE loaded through
`binfmt_elf_fdpic`.

## Building

The kernel is built in a dedicated container (Linux 6.12.97 LTS,
sha256-pinned, clang/LLVM — see [toolchain.md](toolchain.md)):

```
podman build -t rv32mbt-linux -f linux/Dockerfile linux
podman run --rm -v "$PWD:/work" -v rv32mbt-kernel:/kernel \
    -e KERNEL_WORKDIR=/kernel rv32mbt-linux bash linux/build.sh
```

`-v rv32mbt-kernel:/kernel -e KERNEL_WORKDIR=/kernel` keeps the kernel
source and build tree in a named volume, which is much faster on
Windows hosts. On a Linux host both flags can be dropped.

The build produces `_build/kernel/vmlinux` and
`_build/kernel/rv32mbt.dtb`. Boot them with:

```
bash linux/run.sh            # = rv32mbt --dtb rv32mbt.dtb vmlinux
```

`linux/build.sh` also drives `linux/build_userspace.sh`, which fetches
and builds musl, busybox and the compiler-rt builtins (all
sha256-pinned) and assembles the initramfs from
`linux/initramfs.desc`.

## Userspace

busybox 1.36.1 against musl 1.2.5, built as static PIE and loaded as
ELF FDPIC. PID 1 is busybox init (`/init` is a symlink to busybox); it
runs the sysinit entry (`linux/rcS`) from `/etc/inittab` and then
respawns an interactive shell on the console. The shell is hush —
busybox's ash is marked `!NOMMU` in Kconfig and cannot be used here.

`rcS` does two things that matter:

- Mounts `/proc`, `/sys` and `/dev`. `/dev` is devtmpfs mounted
  explicitly because `CONFIG_DEVTMPFS_MOUNT` does not apply to an
  initramfs-only system — the kernel only auto-mounts it on the path
  where it mounts a real root filesystem.
- Runs `busybox --install -s` to lay down applet symlinks in `/bin`
  and `/sbin`. Without them only the shell's built-in resolution works,
  so `which` and exec-by-path fail.

The usual applets are available (`ls`, `ps`, `free`, `grep`, `sed`,
`find`, `vi`, `less`, `top`, …) along with pipes and shell control
flow. A minimal libc-free shell is also kept at `/bin/mini`.

### `/opt/examples` — ordinary userspace programs

The sample programs from `tests/examples/` linked against musl, for
example `/opt/examples/mandelbrot`. They demonstrate that programs
other than busybox run, and their output is byte-for-byte identical to
the bare-metal builds — `tests/examples/sample.h` only switches to
stdio under `__linux__`, so the same `.expect` files verify both.

### `/opt/nested` — running the emulator inside itself

```
/ # /opt/nested/wasmrun /opt/nested/rv32mbt.wasm /opt/nested/hello.elf 2 2000000
hello from rv32mbt
[wasmrun] guest halted, exit=0, steps=104
```

The nesting is rv32mbt → Linux → wasmrun → rv32mbt (wasm) →
`hello.elf`. The inner emulator is the core built for the
linear-memory wasm target; the browser's wasm-gc build needs a
GC-aware host, which a small interpreter is not. `wasmrun`
(`tools/wasmrun/`) is a compact wasm interpreter written for exactly
this job.

Putting the emulator into the guest directly, without wasm in between,
would need a riscv32 MoonBit build. `moonc` only accepts 64-bit
explicit targets and its native runtime is not distributed, so the wasm
route is what is available.

## Power control

`poweroff` goes through init's signal protocol, runs the shutdown
entry, then `reboot(2)` → syscon-poweroff → the sifive_test finisher,
and the emulator exits normally.

`reboot` issues the sifive_test reset request (`0x7777`). The emulator
performs a warm reset — clears RAM, replays the boot images, and
reinitialises the devices and CSRs — and the guest boots again.

## Licensing

The kernel, busybox and musl sources are fetched at build time and are
not part of this repository. See [linux/README.md](../linux/README.md)
for the licence of each component and for the corresponding-source
statement covering the GPL-2.0 `vmlinux` distributed through CI
artifacts and GitHub Pages.
