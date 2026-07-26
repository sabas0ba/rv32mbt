#!/usr/bin/env bash
# Linux boot regression: boot the built kernel and drive the hush
# console the way a terminal would — each line is sent only after the
# guest's own output shows it is ready for it, so the test does not
# depend on how the host buffers a piped stdin.
#
# The whole session runs LINUX_BOOT_ATTEMPTS times (default 3) and
# every attempt must pass: guest-side failures observed so far are
# timing-dependent, and a single lucky run should not turn CI green.
# Every failing attempt prints the console tail plus a symbolized
# oops (ci/resolve_oops.py) so CI logs are diagnosable on their own.
#
# Usage: test_linux_boot.sh [path-to-emulator-binary]
set -euo pipefail
cd "$(dirname "$0")/.."

EMU=${1:-_build/native/release/build/cmd/main/main.exe}
KERNEL=_build/kernel/vmlinux
DTB=_build/kernel/rv32mbt.dtb
EXAMPLES=tests/examples
# Linux-target examples shipped in the initramfs (see
# tests/examples/build_linux.sh and linux/initramfs.desc).
EXAMPLE_NAMES="hello_c fib lifegame mandelbrot primes"
for f in "$EMU" "$KERNEL" "$DTB"; do
  if [[ ! -e $f ]]; then
    echo "missing: $f" >&2
    exit 2
  fi
done

ATTEMPTS=${LINUX_BOOT_ATTEMPTS:-3}
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

diagnose() {
  echo "linux boot[attempt $attempt]: FAILED ($1); last output:" >&2
  tail -150 "$log" >&2 || true
  if command -v python3 >/dev/null 2>&1; then
    python3 ci/resolve_oops.py "$KERNEL" <"$log" >&2 || true
  fi
}

# Poll the console log until a marker has appeared [count] times
# (default once); gives up (returns 1) once the emulator has exited
# (the 300 s timeout bounds a wedged run).
wait_for() {
  local n=${2:-1}
  until [ "$(grep -cF "$1" "$log")" -ge "$n" ]; do
    if ! kill -0 "$emu" 2>/dev/null; then
      # the marker may have been flushed right before exit
      [ "$(grep -cF "$1" "$log")" -ge "$n" ] && return 0
      return 1
    fi
    sleep 1
  done
}

# Run each Linux-target example in the guest and check its output
# byte for byte against the same .expect file the bare-metal build is
# held to.
#
# The program is piped into md5sum so the sum covers the raw stream
# rather than the tty-mangled console echo, and `tee /dev/console`
# puts the program's real output in the log on the way past — a
# console log that only carried hex digests showed neither what ran
# nor whether it passed. The guest compares the digest itself and
# prints the verdict, so the log reads as a transcript.
#
# The markers are split across a string boundary ("EXAMPLE"" fib OK")
# so they appear only in the shell's *output*: the echoed command line
# would otherwise match and pass the check before the program ran.
run_examples() {
  local name sum
  for name in $EXAMPLE_NAMES; do
    sum=$(md5sum <"$EXAMPLES/$name.expect" | cut -d' ' -f1)
    printf 'if /opt/examples/%s | tee /dev/console | md5sum | grep -q %s; then echo "EXAMPLE"" %s OK"; else echo "EXAMPLE"" %s BAD"; fi\n' \
      "$name" "$sum" "$name" "$name" >&3
    # Either verdict ends the wait, so a mismatch fails fast instead
    # of stalling until the emulator timeout.
    if ! wait_for "EXAMPLE $name "; then
      diagnose "example $name: guest printed no verdict"
      return 1
    fi
    if ! grep -qF "EXAMPLE $name OK" "$log"; then
      diagnose "example $name: output does not match $name.expect (md5 $sum)"
      return 1
    fi
    echo "linux boot[attempt $attempt]: example $name OK (md5 $sum)"
  done
  return 0
}

# Drive one console session, stopping at the first failure so the
# diagnostic names the step that actually broke.
drive_session() {
  wait_for "hush - the humble shell" ||
    { diagnose "no interactive shell prompt"; return 1; }
  printf 'uname -a\n' >&3
  # Also assert what rcS brought up: a character device from devtmpfs
  # and an applet symlink from `busybox --install`. The marker only
  # appears in echo's *output*; the echoed command line itself
  # contains the quotes and never matches.
  printf 'test -c /dev/null && test -L /bin/ls && echo RV32""MBT-SHELL-OK\n' >&3
  wait_for "RV32MBT-SHELL-OK" ||
    { diagnose "shell did not run uname, /dev/null or /bin/ls missing"; return 1; }
  # Banner the phase so the console log shows where the userspace
  # examples start, rather than leaving them to blend into the shell
  # session above.
  printf 'echo; echo "== running the Linux-target examples from /opt/examples =="\n' >&3
  run_examples || return 1
  # `reboot` goes through init's shutdown sequence into the
  # sifive_test reset register; the emulator warm-boots and the guest
  # comes up a second time.
  printf 'reboot\n' >&3
  wait_for "hush - the humble shell" 2 ||
    { diagnose "no shell after reboot"; return 1; }
  # A bare `poweroff` also uses init's signal protocol: the shutdown
  # inittab entries run, processes are killed, then the kernel powers
  # off — asserted by the marker list below.
  printf 'poweroff\n' >&3
  return 0
}

run_one() {
  log=$workdir/console.$attempt.log
  fifo=$workdir/in.$attempt
  mkfifo "$fifo"
  # Read-write so neither open blocks and the emulator's stdin never
  # hits EOF between commands.
  exec 3<>"$fifo"
  timeout 300 "$EMU" --max-steps 4000000000 --dtb "$DTB" "$KERNEL" \
    <"$fifo" >"$log" 2>&1 &
  emu=$!

  local ok=1
  if ! drive_session; then
    ok=0
    # The session broke part way through, so the guest will never
    # reach poweroff; stop the emulator rather than waiting out its
    # 300 s timeout on every failing attempt.
    kill "$emu" 2>/dev/null || true
  fi
  exec 3>&-

  local status=0
  wait "$emu" || status=$?
  if ((ok)) && ((status != 0)); then
    diagnose "emulator exit status $status (124 = timeout)"
    ok=0
  fi
  if ((ok)); then
    for pattern in \
      "Run /init as init process" \
      "hush - the humble shell" \
      "Linux" \
      "riscv32" \
      "The system is going down NOW!" \
      "reboot: Restarting system" \
      "reboot: Power down"; do
      if ! grep -qF "$pattern" "$log"; then
        diagnose "missing expected output: $pattern"
        ok=0
        break
      fi
    done
  fi
  ((ok))
}

failed=0
for attempt in $(seq 1 "$ATTEMPTS"); do
  t0=$SECONDS
  if run_one; then
    echo "linux boot[attempt $attempt]: OK ($((SECONDS - t0))s)"
    # Keep the full console log in the CI output even on success.
    # ::group:: renders as a collapsed section on GitHub Actions and
    # is just two plain lines anywhere else.
    echo "::group::linux boot[attempt $attempt] console log"
    cat "$log"
    echo "::endgroup::"
  else
    failed=1
  fi
done
if ((failed)); then
  exit 1
fi
echo "linux boot: OK ($ATTEMPTS/$ATTEMPTS attempts)"
