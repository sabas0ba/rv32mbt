#!/usr/bin/env bash
# Build the bare-metal examples with clang + lld.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p ../build
CLANG=${CLANG:-clang}
"$CLANG" \
  --target=riscv32-unknown-elf \
  -march=rv32ima_zicsr_zifencei -mabi=ilp32 -mcmodel=medany \
  -nostdlib -fuse-ld=lld -static \
  -T ../link32.ld \
  -o ../build/hello.elf hello.S
echo "built ../build/hello.elf"
