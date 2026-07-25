#!/usr/bin/env bash
# Build riscv-tests (rv32ui / rv32um / rv32ua, "p" environment) with
# clang + lld. No riscv-specific GNU toolchain is required.
set -euo pipefail

cd "$(dirname "$0")"
VENDOR=vendor
ENVDIR=$VENDOR/riscv-test-env
ISA=$VENDOR/riscv-tests/isa
OUT=build
mkdir -p "$OUT"

CLANG=${CLANG:-clang}
CFLAGS=(
  --target=riscv32-unknown-elf
  -march=rv32ima_zicsr_zifencei
  -mabi=ilp32
  -mcmodel=medany
  -nostdlib
  -fuse-ld=lld
  -static
  -I "$ENVDIR"
  -I "$ENVDIR/p"
  -I "$ISA/macros/scalar"
  -T link32.ld
)

build_dir() {
  local dir=$1 prefix=$2
  local n=0
  for src in "$ISA/$dir"/*.S; do
    local name
    name=$(basename "$src" .S)
    "$CLANG" "${CFLAGS[@]}" -o "$OUT/$prefix-p-$name.elf" "$src"
    n=$((n + 1))
  done
  echo "built $n tests from $dir"
}

build_dir rv32ui rv32ui
build_dir rv32um rv32um
build_dir rv32ua rv32ua
