# Vendored RISC-V test suite sources

Vendored on: 2026-07-24

All files were fetched via the GitHub API pinned to the exact commit SHAs below,
and every file was verified byte-for-byte against the upstream git blob SHA-1.

## riscv-tests

- Repository: https://github.com/riscv-software-src/riscv-tests
- Commit: 34e6b6d1e7936b526075432fb730d89148623484 (master HEAD at vendoring time)
- License: BSD 3-Clause (University of California, Regents) — see riscv-tests/LICENSE
- Vendored contents (under `riscv-tests/`):
  - LICENSE
  - isa/macros/scalar/test_macros.h
  - isa/rv32ui/*.S (42 files), isa/rv64ui/*.S (54 files)
  - isa/rv32um/*.S (8 files),  isa/rv64um/*.S (13 files)
  - isa/rv32ua/*.S (10 files), isa/rv64ua/*.S (19 files)
  - isa/rv32uc/rvc.S, isa/rv64uc/rvc.S (the rv32 test includes the rv64 file)
  - env/encoding.h — NOTE: in the upstream riscv-tests repo, `env/` is a git
    submodule pointing at riscv/riscv-test-env, so this file does not exist as
    a blob in riscv-tests itself. It was taken from riscv-test-env (commit
    below, top-level encoding.h) and placed here so that `env/encoding.h`
    resolves as the build expects.

## riscv-test-env

- Repository: https://github.com/riscv/riscv-test-env
  (note: this repo lives under the `riscv` org, not `riscv-software-src`;
  it is the target of the `env/` submodule of riscv-tests)
- Commit: a1c373ec89a3500630bafabf406108a8fc568bcc (master HEAD at vendoring time)
- License: BSD 3-Clause (University of California, Regents) — see riscv-test-env/LICENSE
- Vendored contents (under `riscv-test-env/`):
  - LICENSE
  - encoding.h (top level, ~183 KB, auto-generated from riscv-opcodes)
  - p/riscv_test.h ("p" bare-metal single-hart environment)
  - p/link.ld
  - v/ files intentionally omitted (virtual-memory environment not needed).

## Licenses

Both repositories carry the identical BSD 3-Clause license from The Regents of
the University of California. riscv-test-env's encoding.h additionally carries
an SPDX BSD-3-Clause header (Copyright (c) 2023 RISC-V International).
