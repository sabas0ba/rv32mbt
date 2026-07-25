#!/usr/bin/env bash
# Boot the built nommu kernel on the emulator (run inside the
# rv32mbt-dev container, or anywhere the native CLI was built).
#
#   bash linux/run.sh [extra rv32mbt options...]
set -euo pipefail
cd "$(dirname "$0")/.."

EMU=_build/native/release/build/cmd/main/main.exe
KERNEL=_build/kernel/vmlinux
DTB=_build/kernel/rv32mbt.dtb

for f in "$EMU" "$KERNEL" "$DTB"; do
  if [[ ! -e $f ]]; then
    echo "missing: $f (build with ci/run.sh / linux/build.sh)" >&2
    exit 2
  fi
done

exec "$EMU" --dtb "$DTB" "$@" "$KERNEL"
