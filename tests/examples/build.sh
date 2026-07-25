#!/usr/bin/env bash
# Build the bare-metal examples with clang + lld.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p ../build

CLANG=${CLANG:-clang}
CFLAGS=(
  --target=riscv32-unknown-elf
  -march=rv32ima_zicsr_zifencei
  -mabi=ilp32
  -mcmodel=medany
  -Os
  -Wall
  -Wextra
  -Werror
  -ffreestanding
  -nostdlib
  -fuse-ld=lld
  -static
  -T ../link32.ld
)

# Assembly smoke test (no crt0; self-contained).
"$CLANG" "${CFLAGS[@]}" -o ../build/hello.elf hello.S

# C examples share crt0.S and the freestanding support routines.
for src in hello_c fib lifegame; do
  "$CLANG" "${CFLAGS[@]}" -o "../build/$src.elf" crt0.S rt.c "$src.c"
done

echo "built hello, hello_c, fib, lifegame"
