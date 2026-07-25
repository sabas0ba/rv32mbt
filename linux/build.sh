#!/usr/bin/env bash
# Fetch (sha256-pinned), configure and build the nommu RV32 Linux
# kernel with clang/LLVM, and compile the machine DTB. Intended to run
# inside the rv32mbt-linux container (see linux/Dockerfile):
#
#   podman run --rm -v "$PWD:/work" rv32mbt-linux bash linux/build.sh
#
# Outputs:
#   _build/kernel/vmlinux      ELF kernel (boot with: rv32mbt --dtb ...)
#   _build/kernel/rv32mbt.dtb  device tree blob
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

KVER=6.12.97
KSHA256=6cbddfa3bbd2229026f7cc5e48f6b7d6b46d39742de39a9257a2f490a0f45c6f
KURL=https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz

# Final artifacts always land in the repository's _build/kernel/.
# Source tree and build directory live in KERNEL_WORKDIR when set —
# mount a podman named volume there on Windows hosts, where a bind
# mount makes the thousands of small file accesses of a kernel build
# an order of magnitude slower:
#   podman run --rm -v "$PWD:/work" -v rv32mbt-kernel:/kernel \
#       -e KERNEL_WORKDIR=/kernel rv32mbt-linux bash linux/build.sh
OUT=$ROOT/_build/kernel
KDIR=${KERNEL_WORKDIR:-$OUT}
SRC=$KDIR/linux-$KVER
BUILD=$KDIR/build
mkdir -p "$OUT" "$KDIR"

if [[ ! -f $KDIR/linux-$KVER.tar.xz ]]; then
  if [[ -f $OUT/linux-$KVER.tar.xz ]]; then
    cp "$OUT/linux-$KVER.tar.xz" "$KDIR/"
  else
    echo "==> fetching linux-$KVER.tar.xz"
    curl -fL --retry 3 -o "$KDIR/linux-$KVER.tar.xz" "$KURL"
  fi
fi
echo "$KSHA256  $KDIR/linux-$KVER.tar.xz" | sha256sum -c -

if [[ ! -d $SRC ]]; then
  echo "==> extracting"
  tar xf "$KDIR/linux-$KVER.tar.xz" -C "$KDIR"
fi

kmake() {
  make -C "$SRC" ARCH=riscv LLVM=-18 O="$BUILD" -j"$(nproc)" "$@"
}

echo "==> configuring (nommu_virt_defconfig + rv32_nommu.config)"
kmake nommu_virt_defconfig
cat "$ROOT/linux/rv32_nommu.config" >> "$BUILD/.config"
kmake olddefconfig

echo "==> building vmlinux"
kmake vmlinux

cp "$BUILD/vmlinux" "$OUT/vmlinux"

echo "==> compiling rv32mbt.dtb"
dtc -I dts -O dtb -o "$OUT/rv32mbt.dtb" "$ROOT/linux/rv32mbt.dts"

ls -la "$OUT/vmlinux" "$OUT/rv32mbt.dtb"
echo "kernel build OK"
