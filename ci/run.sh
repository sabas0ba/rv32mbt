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

echo "==> moon check"
moon check

echo "==> moon test --target native"
moon test --target native

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

echo "==> moon build --target js --release web"
moon build --target js --release web

echo "==> CI OK"
