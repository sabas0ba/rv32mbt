# Pinned toolchain

The development and CI environment is built from the `Dockerfile` at
the repository root (podman and docker both work). GitHub Actions
(`.github/workflows/ci.yml`) and the devcontainer
(`.devcontainer/devcontainer.json`) use the same Dockerfile.

## Usage

```
podman build -t rv32mbt-dev .
podman run --rm -v "$PWD:/work" rv32mbt-dev bash ci/run.sh   # full regression
podman run --rm -v "$PWD:/work" rv32mbt-dev moon check       # a single command
```

## Pinned versions

| Component | Pinned value |
|---|---|
| base image | ubuntu:24.04 @sha256:52df9b1ee71626e0088f7d400d5c6b5f7bb916f8f0c82b474289a4ece6cf3faf |
| moon | 0.1.20260724 (5f1406a 2026-07-24) |
| moonc | v0.10.5+5e7afb0c0 (2026-07-27) |
| moonrun | 0.1.20260724 (5f1406a 2026-07-24) |
| clang / lld | 18.1.3 (Ubuntu 1:18.1.3-1ubuntu1, apt) |
| python3 | 3.12 (Ubuntu 24.04 apt) |
| dtc | Ubuntu 24.04 apt (device-tree-compiler) |

- The sha256 digests below are the authority. The Dockerfile installs a
  tarball only when its digest matches the pin, so no other version can
  get in regardless of what the server returned; `moon version` is
  asserted afterwards as a readable second check.
- `cli.moonbitlang.com` publishes only `binaries/latest` and
  `cores/core-latest.tar.gz`, and rotates them in place. Dated archive
  paths were tried in CI — `binaries/<date>/`, `binaries/nightly-<date>/`,
  `binaries/<version>/` and the matching `cores/core-<...>.tar.gz` — and
  none of them exist. **A pinned build therefore becomes unobtainable as
  soon as upstream publishes**, and the pins have to move forward; they
  cannot be held back.
- Because of that, the digest check is a change detector rather than a
  guarantee of reproducibility: it stops an unnoticed version from being
  installed, but it cannot reconstruct an older toolchain. Anyone
  building an old commit of this repository will need the pins from a
  build that upstream still serves.
- Both tarballs are fetched and their digests printed before either is
  checked, so a single failed build reports every value a bump needs.
  - moonbit-linux-x86_64.tar.gz:
    `717de2d53623f57c5d8eec9f8ec55c75174d9b41d081410e632af1f61509ad1f`
  - core-latest.tar.gz:
    `4384f9ffa7505677787ed6776d8283ce43b5090eab80295c3e06731393f5d7b8`
- The apt packages are determined by the base image digest and the
  archive contents at build time. The table above records the versions
  that were actually installed.
- The riscv-tests sources are fetched by `tests/fetch_vendor.sh`, pinned
  by commit SHA and verified by sha256; see
  [../tests/VENDOR-MANIFEST.md](../tests/VENDOR-MANIFEST.md).

## Linux kernel build environment (`linux/Dockerfile`)

The nommu RV32 kernel is built in a separate image, `rv32mbt-linux`
(same base image digest as above). No cross toolchain is used; the
build runs on clang/LLVM via `make LLVM=-18`.

| Component | Pinned value |
|---|---|
| linux | 6.12.97 (LTS) |
| linux-6.12.97.tar.xz sha256 | `6cbddfa3bbd2229026f7cc5e48f6b7d6b46d39742de39a9257a2f490a0f45c6f` |
| source | cdn.kernel.org/pub/linux/kernel/v6.x/ |

The kernel source is not baked into the image; `linux/build.sh` fetches
it, verifies the sha256 and unpacks it under `_build/kernel/` (which is
gitignored). The configuration is `nommu_virt_defconfig` plus
`linux/rv32_nommu.config` (the RV32 switch and related options).

## Userspace (`linux/build_userspace.sh`)

The busybox userspace is built in the same image. Its sources are also
fetched at build time and sha256-pinned:

| Component | Version | sha256 |
|---|---|---|
| musl | 1.2.5 | `a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4` |
| busybox | 1.36.1 | `b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314` |
| compiler-rt (builtins) | 18.1.3 | `9a7df9300413696b0c4f7ff1e2729cb82aca375f35c05d698c44f26a4edf1c27` |
| llvm cmake modules | 18.1.3 | `acfecb615d41c5b1a0a31e15324994ca06f7a3f37d8958d719b20de0d217b71b` |

- The compiler-rt builtins for rv32 are not part of Ubuntu's llvm-18, so
  they are built from source (this adds cmake, llvm-18-dev and bzip2 to
  the image).
- musl is built statically for riscv32 with clang and llvm-ar.
- busybox is `allnoconfig` plus `linux/busybox.config` (hush, NOMMU,
  static PIE). ash cannot be used: Kconfig marks it `!NOMMU`.
- The Linux UAPI headers are copied into the sysroot from the kernel
  tree's `make headers`.

## Updating a pinned version

1. Get the sha256 of the new tarballs and update `MOONBIT_SHA256`,
   `CORE_SHA256` and `MOON_VERSION` in the Dockerfile (or the base
   image digest). A failing build prints both digests it received, or
   compute them directly:

   ```
   curl -fsSL https://cli.moonbitlang.com/binaries/latest/moonbit-linux-x86_64.tar.gz | sha256sum
   curl -fsSL https://cli.moonbitlang.com/cores/core-latest.tar.gz | sha256sum
   ```
2. Run `podman build`, then update the table above from the output of
   `moon version --all`.
3. Run `bash ci/run.sh` to completion inside the container before
   committing.
