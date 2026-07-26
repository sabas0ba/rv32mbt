#!/usr/bin/env bash
# Build the wasm interpreter and stage everything the guest needs to
# run the emulator inside itself:
#
#   rv32mbt -> Linux -> wasmrun -> rv32mbt (wasm) -> program.elf
#
# Outputs into _build/kernel/ for linux/initramfs.desc to pick up:
#   wasmrun        the interpreter, riscv32-linux-musl
#   rv32mbt.wasm   the emulator core as a linear-memory wasm module
#   hello.elf      a bare-metal program to run inside it
#
# Called by linux/build.sh. CC_HOST=1 builds a host binary instead,
# which is how the interpreter is exercised during development.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

OUT=$ROOT/_build/kernel
SRC=("$ROOT/tools/wasmrun/wasm.c" "$ROOT/tools/wasmrun/main.c")

if [[ ${CC_HOST:-0} = 1 ]]; then
  mkdir -p "$OUT"
  ${CC:-clang} -O2 -Wall -Wextra -Werror -o "$OUT/wasmrun-host" "${SRC[@]}"
  echo "built _build/kernel/wasmrun-host"
  exit 0
fi

KDIR=${KERNEL_WORKDIR:-$OUT}
CC_WRAP=$KDIR/userspace/cc-rv32
if [[ ! -x $CC_WRAP ]]; then
  echo "missing: $CC_WRAP (run linux/build_userspace.sh first)" >&2
  exit 2
fi

mkdir -p "$OUT"
"$CC_WRAP" -Os -Wall -Wextra -Werror -o "$OUT/wasmrun" "${SRC[@]}"
if llvm-readelf-18 -l "$OUT/wasmrun" | grep -q INTERP; then
  echo "error: wasmrun requests a dynamic interpreter" >&2
  exit 1
fi

# The emulator core, built for the linear-memory wasm target: the
# wasm-gc module the browser uses needs a GC-aware host, which a small
# interpreter is not.
#
# This script normally runs in the kernel image, which carries
# clang/LLVM but not MoonBit, so an already-built module is used when
# `moon` is absent (CI builds it in the toolchain image first).
WASM=$ROOT/_build/wasm/release/build/wasm/wasm.wasm
if command -v moon >/dev/null 2>&1; then
  moon build --target wasm --release wasm
elif [[ ! -f $WASM ]]; then
  echo "error: no MoonBit toolchain here and no prebuilt $WASM." >&2
  echo "       run 'moon build --target wasm --release wasm' first." >&2
  exit 2
fi
cp "$WASM" "$OUT/rv32mbt.wasm"

# Something for the nested emulator to run. The bare-metal hello is
# the cheapest program that produces output, which matters because
# every instruction costs an interpreted wasm call inside an emulated
# machine.
if [[ ! -f $ROOT/tests/build/hello.elf ]]; then
  bash "$ROOT/tests/examples/build.sh"
fi
cp "$ROOT/tests/build/hello.elf" "$OUT/hello.elf"

ls -la "$OUT/wasmrun" "$OUT/rv32mbt.wasm" "$OUT/hello.elf"
echo "nested-emulator payload OK"
