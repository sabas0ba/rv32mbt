#!/usr/bin/env bash
# Run all built riscv-tests ELFs on the emulator and report pass/fail.
# Usage: run_tests.sh [path-to-emulator-binary]
set -uo pipefail

cd "$(dirname "$0")"
EMU=${1:-../_build/native/release/build/cmd/main/main.exe}
if [[ ! -x $EMU ]]; then
  echo "emulator binary not found: $EMU" >&2
  exit 2
fi

pass=0
fail=0
failed=()
for elf in build/*.elf; do
  if "$EMU" --quiet --max-steps 10000000 "$elf" >/dev/null 2>&1; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    failed+=("$(basename "$elf")")
  fi
done

echo "riscv-tests: pass=$pass fail=$fail"
if ((fail > 0)); then
  printf 'failed: %s\n' "${failed[@]}"
  exit 1
fi
