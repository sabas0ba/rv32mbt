#!/usr/bin/env bash
# Linux boot regression: boot the built kernel, drive the interactive
# init over the console and expect a clean finisher exit.
# Usage: test_linux_boot.sh [path-to-emulator-binary]
set -euo pipefail
cd "$(dirname "$0")/.."

EMU=${1:-_build/native/release/build/cmd/main/main.exe}
KERNEL=_build/kernel/vmlinux
DTB=_build/kernel/rv32mbt.dtb
for f in "$EMU" "$KERNEL" "$DTB"; do
  if [[ ! -e $f ]]; then
    echo "missing: $f" >&2
    exit 2
  fi
done

out=$(printf 'uname -a\npoweroff\n' |
  timeout 300 "$EMU" --quiet --max-steps 4000000000 --dtb "$DTB" "$KERNEL" 2>&1)

fail=0
for pattern in \
  "Run /init as init process" \
  "hush - the humble shell" \
  "Linux" \
  "riscv32" \
  "reboot: Power down"; do
  if ! grep -qF "$pattern" <<<"$out"; then
    echo "linux boot: missing expected output: $pattern" >&2
    fail=1
  fi
done
if ((fail)); then
  tail -30 <<<"$out" >&2
  exit 1
fi
echo "linux boot: OK"
