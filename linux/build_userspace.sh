#!/usr/bin/env bash
# Build the busybox userspace for the initramfs. All sources are
# fetched at build time and sha256-pinned; nothing is vendored:
#   compiler-rt builtins (rv32; the distro llvm lacks them)
#   musl (static libc for riscv32)
#   busybox (static PIE, NOMMU, ash + core applets)
# Runs inside the rv32mbt-linux container. Called by linux/build.sh;
# outputs _build/kernel/busybox.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

MUSL_VER=1.2.5
MUSL_SHA256=a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4
BB_VER=1.36.1
BB_SHA256=b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314
CRT_VER=18.1.3
CRT_SHA256=9a7df9300413696b0c4f7ff1e2729cb82aca375f35c05d698c44f26a4edf1c27
# shared cmake modules used by the standalone compiler-rt build
LLVM_CMAKE_SHA256=acfecb615d41c5b1a0a31e15324994ca06f7a3f37d8958d719b20de0d217b71b

OUT=$ROOT/_build/kernel
KDIR=${KERNEL_WORKDIR:-$OUT}
US=$KDIR/userspace
SYSROOT=$US/sysroot
TARGET=riscv32-unknown-linux-musl
MARCH="-march=rv32imac_zicsr_zifencei -mabi=ilp32"
mkdir -p "$OUT" "$US" "$SYSROOT/lib"

fetch() { # fetch <url> <dest> <sha256>
  if [[ ! -f $2 ]]; then
    echo "==> fetching $(basename "$2")"
    # --retry alone does not cover mid-transfer connection resets,
    # which musl.libc.org produces now and then; the sha256 check
    # still gates whatever ends up on disk
    curl -fL --retry 5 --retry-all-errors --retry-delay 5 -o "$2" "$1"
  fi
  echo "$3  $2" | sha256sum -c -
}

fetch "https://musl.libc.org/releases/musl-$MUSL_VER.tar.gz" \
  "$US/musl-$MUSL_VER.tar.gz" "$MUSL_SHA256"
fetch "https://busybox.net/downloads/busybox-$BB_VER.tar.bz2" \
  "$US/busybox-$BB_VER.tar.bz2" "$BB_SHA256"
fetch "https://github.com/llvm/llvm-project/releases/download/llvmorg-$CRT_VER/compiler-rt-$CRT_VER.src.tar.xz" \
  "$US/compiler-rt-$CRT_VER.src.tar.xz" "$CRT_SHA256"
fetch "https://github.com/llvm/llvm-project/releases/download/llvmorg-$CRT_VER/cmake-$CRT_VER.src.tar.xz" \
  "$US/cmake-$CRT_VER.src.tar.xz" "$LLVM_CMAKE_SHA256"

# --- compiler-rt builtins --------------------------------------------
BUILTINS=$SYSROOT/lib/libclang_rt.builtins-riscv32.a
if [[ ! -f $BUILTINS ]]; then
  echo "==> compiler-rt builtins (rv32)"
  rm -rf "$US/compiler-rt-$CRT_VER.src" "$US/cmake-$CRT_VER.src" "$US/crt-build"
  tar xf "$US/compiler-rt-$CRT_VER.src.tar.xz" -C "$US"
  tar xf "$US/cmake-$CRT_VER.src.tar.xz" -C "$US"
  # the standalone build expects the shared modules at ../cmake; the
  # LLVM cmake definitions come from the distro llvm-18-dev package
  ln -sfn "cmake-$CRT_VER.src" "$US/cmake"
  # freestanding build: a stub sysroot keeps host glibc headers out.
  # clear_cache.c needs assert.h (no-op stub) and linux/unistd.h for
  # __NR_riscv_flush_icache (244 + 15 per the riscv uapi).
  mkdir -p "$US/empty-sysroot/usr/include/linux"
  printf '#define assert(x) ((void)0)\n' \
    > "$US/empty-sysroot/usr/include/assert.h"
  printf '#define __NR_riscv_flush_icache 259\n' \
    > "$US/empty-sysroot/usr/include/linux/unistd.h"
  cmake -S "$US/compiler-rt-$CRT_VER.src/lib/builtins" -B "$US/crt-build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=riscv32 \
    -DCMAKE_C_COMPILER=clang-18 \
    -DCMAKE_C_COMPILER_TARGET=$TARGET \
    -DCMAKE_ASM_COMPILER=clang-18 \
    -DCMAKE_ASM_COMPILER_TARGET=$TARGET \
    -DCMAKE_AR=/usr/bin/llvm-ar-18 \
    -DCMAKE_RANLIB=/usr/bin/llvm-ranlib-18 \
    -DCMAKE_C_FLAGS="$MARCH -ffreestanding --sysroot=$US/empty-sysroot" \
    -DCMAKE_ASM_FLAGS="$MARCH --sysroot=$US/empty-sysroot" \
    -DCMAKE_C_COMPILER_WORKS=1 \
    -DLLVM_CMAKE_DIR=/usr/lib/llvm-18/lib/cmake/llvm \
    -DCOMPILER_RT_BAREMETAL_BUILD=ON \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
    > "$US/crt-cmake.log"
  cmake --build "$US/crt-build" -j"$(nproc)" > "$US/crt-make.log"
  find "$US/crt-build" -name 'libclang_rt.builtins*.a' \
    -exec cp {} "$BUILTINS" \;
  test -f "$BUILTINS"
fi

# A private clang resource dir so the driver finds the rv32 builtins
# and crtbegin/crtend (--rtlib=compiler-rt) while keeping the
# compiler's own headers.
CLANGRT=$US/clangrt
if [[ ! -f $CLANGRT/lib/linux/clang_rt.crtbegin-riscv32.o ]]; then
  rm -rf "$CLANGRT"
  RES=$(clang-18 -print-resource-dir)
  mkdir -p "$CLANGRT/lib/linux"
  cp -r "$RES/include" "$CLANGRT/include"
  cp "$BUILTINS" "$CLANGRT/lib/linux/libclang_rt.builtins-riscv32.a"
  find "$US/crt-build" -name 'clang_rt.crtbegin*.o' \
    -exec cp {} "$CLANGRT/lib/linux/clang_rt.crtbegin-riscv32.o" \;
  find "$US/crt-build" -name 'clang_rt.crtend*.o' \
    -exec cp {} "$CLANGRT/lib/linux/clang_rt.crtend-riscv32.o" \;
  test -f "$CLANGRT/lib/linux/clang_rt.crtbegin-riscv32.o"
  test -f "$CLANGRT/lib/linux/clang_rt.crtend-riscv32.o"
fi

# --- musl -------------------------------------------------------------
if [[ ! -f $SYSROOT/lib/libc.a ]]; then
  echo "==> musl"
  rm -rf "$US/musl-$MUSL_VER"
  tar xf "$US/musl-$MUSL_VER.tar.gz" -C "$US"
  # musl 1.2.5 has no riscv32 vfork.s, so vfork() falls back to the
  # generic C clone(SIGCHLD, 0) — plain fork semantics. The nommu
  # kernel does not reject a clone without CLONE_VM (dup_mmap is a
  # stub), so that "fork" yields a child sharing all memory with a
  # parent that is NOT suspended: both race on the same stack and the
  # loser returns through clobbered frames (observed as hush jumping
  # to 0 after setpgid, timing-dependent). Install the riscv64
  # vfork.s that musl gained after 1.2.5 as the riscv32 version: the
  # instructions and clone ABI are XLEN-independent and __NR_clone is
  # 220 on both.
  mkdir -p "$US/musl-$MUSL_VER/src/process/riscv32"
  cat > "$US/musl-$MUSL_VER/src/process/riscv32/vfork.s" <<'EOF'
.global vfork
.type vfork,@function
vfork:
	/* riscv does not have SYS_vfork, so we must use clone instead */
	/* note: riscv's clone = clone(flags, sp, ptidptr, tls, ctidptr) */
	li a7, 220
	li a0, 0x100 | 0x4000 | 17 /* flags = CLONE_VM | CLONE_VFORK | SIGCHLD */
	mv a1, sp
	/* the other arguments are ignoreable */
	ecall
	.hidden __syscall_ret
	j __syscall_ret
EOF
  (
    cd "$US/musl-$MUSL_VER"
    CC=clang-18 \
      CFLAGS="--target=$TARGET $MARCH -resource-dir=$CLANGRT" \
      LIBCC="$BUILTINS" \
      AR=llvm-ar-18 RANLIB=llvm-ranlib-18 \
      ./configure --target=riscv32 --prefix="$SYSROOT" --disable-shared \
      > "$US/musl-configure.log"
    make -j"$(nproc)" AR=llvm-ar-18 RANLIB=llvm-ranlib-18 \
      > "$US/musl-make.log"
    make install AR=llvm-ar-18 RANLIB=llvm-ranlib-18 > /dev/null
  )
fi

# --- cc wrapper -------------------------------------------------------
CC_WRAP=$US/cc-rv32
cat > "$CC_WRAP" <<EOF
#!/bin/sh
# -static-pie only applies to full links; busybox also does partial
# links (cc -r) where it conflicts. -fPIE keeps the objects PIC.
pie=-static-pie
for a in "\$@"; do
  if [ "\$a" = "-r" ]; then pie=""; break; fi
done
exec clang-18 --target=$TARGET $MARCH \\
  --sysroot=$SYSROOT -resource-dir=$CLANGRT \\
  --rtlib=compiler-rt --unwindlib=none \\
  -fuse-ld=lld -fPIE \$pie "\$@"
EOF
chmod +x "$CC_WRAP"

# --- kernel uapi headers (busybox needs linux/*.h) --------------------
if [[ ! -d $SYSROOT/include/linux ]]; then
  echo "==> kernel uapi headers"
  KSRC=$(ls -d "$KDIR"/linux-*/ 2>/dev/null | head -1)
  if [[ -z $KSRC ]]; then
    echo "error: kernel source not found in $KDIR (run linux/build.sh once)" >&2
    exit 1
  fi
  # `headers` generates usr/include in the build dir; copy it manually
  # (the headers_install rule needs rsync, which the image lacks)
  make -C "$KSRC" O="$KDIR/build" ARCH=riscv HOSTCC=clang-18 headers \
    > "$US/headers.log"
  cp -r "$KDIR/build/usr/include/." "$SYSROOT/include/"
fi

# --- busybox ----------------------------------------------------------
BB_SRC=$US/busybox-$BB_VER
if [[ ! -f $BB_SRC/busybox ]]; then
  echo "==> busybox"
  rm -rf "$BB_SRC"
  tar xf "$US/busybox-$BB_VER.tar.bz2" -C "$US"
  make -C "$BB_SRC" HOSTCC=clang-18 allnoconfig > /dev/null
  # busybox's old kconfig keeps the first definition it sees, so drop
  # the allnoconfig lines before appending the fragment values
  # (both CONFIG_X=... and "# CONFIG_X is not set" forms)
  while IFS= read -r line; do
    name=""
    case $line in
      CONFIG_*=*) name=${line%%=*} ;;
      "# CONFIG_"*" is not set") name=${line#"# "}; name=${name%" is not set"} ;;
    esac
    if [[ -n $name ]]; then
      sed -i "/^# $name is not set\$/d; /^$name=/d" "$BB_SRC/.config"
      printf '%s\n' "$line" >> "$BB_SRC/.config"
    fi
  done < "$ROOT/linux/busybox.config"
  # accept defaults for every new prompt (finite input; `yes |` would
  # die of SIGPIPE under pipefail)
  printf '\n%.0s' $(seq 500) | make -C "$BB_SRC" HOSTCC=clang-18 \
    oldconfig > /dev/null
  make -C "$BB_SRC" -j"$(nproc)" HOSTCC=clang-18 CC="$CC_WRAP" \
    SKIP_STRIP=y > "$US/busybox-make.log"
fi
llvm-strip-18 -o "$OUT/busybox" "$BB_SRC/busybox"

# The FDPIC loader maps ET_DYN executables with a constant
# displacement; a dynamic interpreter must not be requested.
if llvm-readelf-18 -l "$OUT/busybox" | grep -q INTERP; then
  echo "error: busybox requests a dynamic interpreter" >&2
  exit 1
fi
ls -la "$OUT/busybox"
echo "userspace build OK"
