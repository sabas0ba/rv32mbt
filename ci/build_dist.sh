#!/usr/bin/env bash
# Build the release artifacts into _build/dist/:
#   rv32mbt-linux-x86_64  native CLI binary
#   rv32mbt-vm.wasm       wasm-gc VM module (Int-only export surface)
#   site/                 static web site (frontend + sample ELFs)
set -euo pipefail
cd "$(dirname "$0")/.."

DIST=_build/dist
rm -rf "$DIST"
mkdir -p "$DIST"

moon build --target native --release cmd/main
cp _build/native/release/build/cmd/main/main.exe "$DIST/rv32mbt-linux-x86_64"

moon build --target wasm-gc --release wasm
cp _build/wasm-gc/release/build/wasm/wasm.wasm "$DIST/rv32mbt-vm.wasm"

bash ci/build_site.sh
cp -r _build/site "$DIST/site"

ls -la "$DIST"
echo "dist assembled in $DIST"
