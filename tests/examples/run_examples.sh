#!/usr/bin/env bash
# Run each example on the emulator and compare the UART output with the
# committed .expect file. Usage: run_examples.sh [path-to-emulator]
set -uo pipefail
cd "$(dirname "$0")"

EMU=${1:-../../_build/native/release/build/cmd/main/main.exe}
if [[ ! -x $EMU ]]; then
  echo "emulator binary not found: $EMU" >&2
  exit 2
fi

fail=0
for name in hello hello_c fib lifegame; do
  elf=../build/$name.elf
  expect=$name.expect
  out=$("$EMU" --quiet --max-steps 10000000 "$elf" 2>&1)
  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "FAIL $name: exit=$rc"
    fail=1
  elif [[ $out != "$(cat "$expect")" ]]; then
    echo "FAIL $name: output mismatch"
    diff <(printf '%s\n' "$out") "$expect" | head -20
    fail=1
  else
    echo "PASS $name"
  fi
done
exit $fail
