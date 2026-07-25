#!/usr/bin/env bash
# Build riscv-tests (rv32ui / rv32um / rv32ua / rv32uc, "p"
# environment) with clang + lld. No riscv-specific GNU toolchain is
# required.
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

build_dir() { # build_dir <isa-subdir> <output-prefix> <march>
  local dir=$1 prefix=$2 march=$3
  local n=0
  for src in "$ISA/$dir"/*.S; do
    local name
    name=$(basename "$src" .S)
    "$CLANG" "${CFLAGS[@]}" "-march=$march" -o "$OUT/$prefix-p-$name.elf" "$src"
    n=$((n + 1))
  done
  echo "built $n tests from $dir"
}

build_dir rv32ui rv32ui rv32ima_zicsr_zifencei
build_dir rv32um rv32um rv32ima_zicsr_zifencei
build_dir rv32ua rv32ua rv32ima_zicsr_zifencei
build_dir rv32uc rv32uc rv32imac_zicsr_zifencei
