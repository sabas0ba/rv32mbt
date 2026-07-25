#!/usr/bin/env bash
# Assemble the static web site (browser frontend + sample ELFs) into
# _build/site/. Runs inside the rv32mbt-dev container or any
# environment with moon, clang and lld on PATH.
set -euo pipefail
cd "$(dirname "$0")/.."

moon build --target js --release web
bash tests/examples/build.sh

SITE=_build/site
rm -rf "$SITE"
mkdir -p "$SITE/samples"
cp web/index.html "$SITE/"
cp _build/js/release/build/web/web.js "$SITE/"
for n in hello hello_c fib lifegame mandelbrot primes; do
  cp "tests/build/$n.elf" "$SITE/samples/"
done

# Linux sample (built separately by linux/build.sh; optional locally,
# always present in the Pages deployment)
if [[ -f _build/kernel/vmlinux && -f _build/kernel/rv32mbt.dtb ]]; then
  cp _build/kernel/vmlinux _build/kernel/rv32mbt.dtb "$SITE/samples/"
else
  echo "note: _build/kernel/{vmlinux,rv32mbt.dtb} not found; the Linux" \
       "sample will 404 (build with linux/build.sh)"
fi

echo "site assembled in $SITE"
