#!/usr/bin/env bash
# Build the C examples as Linux userspace programs, against the musl
# sysroot that linux/build_userspace.sh produces. Same sources as the
# bare-metal build (tests/examples/build.sh) — sample.h switches to
# stdio when __linux__ is defined — so the committed .expect files
# cover both, and running these in the guest exercises the emulator's
# U-mode and syscall path with programs other than busybox.
#
# Called by linux/build.sh; outputs _build/kernel/examples/.
set -euo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

KDIR=${KERNEL_WORKDIR:-$ROOT/_build/kernel}
CC_WRAP=$KDIR/userspace/cc-rv32
OUT=$ROOT/_build/kernel/examples

if [[ ! -x $CC_WRAP ]]; then
  echo "missing: $CC_WRAP (run linux/build_userspace.sh first)" >&2
  exit 2
fi

mkdir -p "$OUT"
for src in hello_c fib lifegame mandelbrot primes; do
  "$CC_WRAP" -Os -Wall -Wextra -Werror \
    -o "$OUT/$src" "$ROOT/tests/examples/$src.c"
  # The FDPIC loader maps ET_DYN executables without consulting an
  # interpreter, so requesting one would fail at exec time.
  if llvm-readelf-18 -l "$OUT/$src" | grep -q INTERP; then
    echo "error: $src requests a dynamic interpreter" >&2
    exit 1
  fi
done

echo "built linux examples: hello_c fib lifegame mandelbrot primes"
