#!/usr/bin/env bash
# Linux boot regression: boot the built kernel and drive the hush
# console the way a terminal would — each line is sent only after the
# guest's own output shows it is ready for it, so the test does not
# depend on how the host buffers a piped stdin.
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

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
fifo=$workdir/console-in
log=$workdir/console.log
mkfifo "$fifo"

timeout 300 "$EMU" --max-steps 4000000000 --dtb "$DTB" "$KERNEL" \
  <"$fifo" >"$log" 2>&1 &
emu=$!
# Hold a writer on the fifo for the whole session so the emulator's
# stdin never hits EOF between commands.
exec 3>"$fifo"

fail() {
  echo "linux boot: FAILED ($1); last output:" >&2
  tail -30 "$log" >&2 || true
  exit 1
}

# Poll the console log until a marker appears (the emulator halting or
# the 300 s timeout ends the wait with a failure).
wait_for() {
  until grep -qF "$1" "$log"; do
    if ! kill -0 "$emu" 2>/dev/null; then
      # the marker may have been flushed right before exit
      grep -qF "$1" "$log" && return 0
      return 1
    fi
    sleep 1
  done
}

send() {
  printf '%s\n' "$1" >&3
}

wait_for "hush - the humble shell" || fail "no interactive shell prompt"
send 'uname -a'
# The marker only appears in echo's *output*; the echoed command line
# itself contains the quotes and never matches.
send 'echo RV32""MBT-SHELL-OK'
wait_for "RV32MBT-SHELL-OK" || fail "shell did not run uname"
send 'poweroff'
exec 3>&-

status=0
wait "$emu" || status=$?
((status == 0)) || fail "emulator exit status $status (124 = timeout)"

for pattern in \
  "Run /init as init process" \
  "hush - the humble shell" \
  "Linux" \
  "riscv32" \
  "reboot: Power down"; do
  grep -qF "$pattern" "$log" || fail "missing expected output: $pattern"
done
echo "linux boot: OK"
