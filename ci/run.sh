#!/usr/bin/env bash
# Full regression: check, unit tests, native build, riscv-tests, js build.
# Intended to run inside the rv32mbt-dev container (see Dockerfile):
#
#   podman run --rm -v "$PWD:/work" rv32mbt-dev bash ci/run.sh
#
# but works in any environment that has moon, clang and lld on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> toolchain"
moon version --all
clang --version | head -1

# The version lives in two places that cannot import each other:
# moon.mod (package metadata) and core/version.mbt (what the binaries
# report). Fail early rather than ship a binary that lies about itself.
echo "==> version"
MOD_VERSION=$(sed -n 's/^version *= *"\(.*\)"/\1/p' moon.mod)
SRC_VERSION=$(sed -n 's/.*VERSION *: *String *= *"\(.*\)"/\1/p' core/version.mbt)
if [[ -z $MOD_VERSION || $MOD_VERSION != "$SRC_VERSION" ]]; then
  echo "version mismatch: moon.mod=$MOD_VERSION core/version.mbt=$SRC_VERSION" >&2
  exit 1
fi
echo "rv32mbt $MOD_VERSION"

echo "==> moon check"
moon check

echo "==> moon test --target native"
moon test --target native

echo "==> moon test --target wasm-gc (wasm api)"
moon test --target wasm-gc -p sabas0ba/rv32mbt/wasm

echo "==> moon build --target native --release cmd/main"
moon build --target native --release cmd/main

EMU=_build/native/release/build/cmd/main/main.exe
if [[ ! -x $EMU ]]; then
  echo "emulator binary not found: $EMU" >&2
  exit 1
fi

echo "==> riscv-tests"
bash tests/fetch_vendor.sh
bash tests/build_tests.sh
bash tests/run_tests.sh "$(pwd)/$EMU"

echo "==> examples"
bash tests/examples/build.sh
bash tests/examples/run_examples.sh "$(pwd)/$EMU"

# Linux boot regression. RUN_LINUX_BOOT: auto (default) = run when the
# kernel artifacts exist, 1 = require them, 0 = skip. Build them with
# linux/build.sh (slow; cached in CI keyed on linux/**).
echo "==> linux boot (RUN_LINUX_BOOT=${RUN_LINUX_BOOT:-auto})"
case ${RUN_LINUX_BOOT:-auto} in
  0) echo "linux boot: skipped" ;;
  1) bash ci/test_linux_boot.sh "$(pwd)/$EMU" ;;
  *)
    if [[ -f _build/kernel/vmlinux && -f _build/kernel/rv32mbt.dtb ]]; then
      bash ci/test_linux_boot.sh "$(pwd)/$EMU"
    else
      echo "linux boot: skipped (no _build/kernel/vmlinux; run linux/build.sh)"
    fi
    ;;
esac

echo "==> moon build --target js --release web"
moon build --target js --release web

echo "==> CI OK"
