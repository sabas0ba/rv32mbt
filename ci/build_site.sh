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
for n in hello hello_c fib lifegame; do
  cp "tests/build/$n.elf" "$SITE/samples/"
done

echo "site assembled in $SITE"
