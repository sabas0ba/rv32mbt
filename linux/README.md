# Licensing for `linux/`

- Every file in this directory (`Dockerfile`, `build*.sh`, `run.sh`,
  `rv32mbt.dts`, `rv32_nommu.config`, `busybox.config`, `init.c`,
  `inittab`, `rcS`, `initramfs.desc`) is Apache-2.0, under the
  `LICENSE` at the repository root. It is original to this repository
  and contains no copies of upstream sources, with one exception: the
  riscv32 `vfork.s` that `build_userspace.sh` applies to musl is a copy
  of musl's own riscv64 implementation (MIT; see musl's COPYRIGHT).
- Upstream sources fetched at build time (not part of this repository;
  all sha256-pinned, see [../docs/toolchain.md](../docs/toolchain.md)):
  - Linux kernel: GPL-2.0 (with the syscall exception)
  - busybox: GPL-2.0
  - musl: MIT
  - compiler-rt: Apache-2.0 WITH LLVM-exception

## Corresponding source for distributed binaries

The `vmlinux` distributed through the CI artifacts and GitHub Pages is
GPL-2.0 (the kernel plus busybox inside the initramfs). It is fully
reproducible from the following.

| Item | Contents |
|---|---|
| Sources | linux-6.12.97.tar.xz, busybox-1.36.1.tar.bz2, musl-1.2.5.tar.gz, compiler-rt-18.1.3.src.tar.xz — each from its official site, unmodified and unpatched |
| Configuration | `nommu_virt_defconfig` + `linux/rv32_nommu.config`; `allnoconfig` + `linux/busybox.config` |
| Procedure | `linux/Dockerfile` + `linux/build.sh` (which drives `build_userspace.sh`) |
