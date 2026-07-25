# rv32mbt

MoonBit による RV32IMA エミュレータ。QEMU virt 互換のメモリマップ
（UART 16550 / CLINT / PLIC / sifive_test）を実装する。native backend の
CLI と js backend のブラウザフロントエンドの両方に対応する。最終目標は
nommu Linux (CONFIG_RISCV_M_MODE) の起動。設計・段階計画は
docs/design.md を参照。

## 開発環境

ツールチェーンは Dockerfile で固定する（詳細は docs/toolchain.md）。
podman でも docker でも動作する。

```
podman build -t rv32mbt-dev .
podman run --rm -v "$PWD:/work" rv32mbt-dev bash ci/run.sh
```

`ci/run.sh` は次を順に実行する:

1. `moon check`
2. `moon test --target native`（コアのユニットテスト）
3. `moon build --target native --release cmd/main`（CLI バイナリ）
4. riscv-tests の取得・ビルド・実行（tests/ 参照、60 本）
5. `moon build --target js --release web`（ブラウザ用モジュール）

GitHub Actions（.github/workflows/ci.yml）は push / PR ごとに同じ
イメージをビルドして `ci/run.sh` を実行する。VS Code の devcontainer
（.devcontainer/）も同じ Dockerfile を使う。

## CLI の使い方

```
moon build --target native --release cmd/main
<出力バイナリ> [--quiet] [--max-steps N] [--bin --load-addr ADDR] <image.elf>
```

ELF32 (RV32) 実行ファイルを DRAM（0x80000000）にロードして実行する。
UART 出力は標準出力へ流れる。riscv-tests の HTIF (`tohost`) と
sifive_test の finisher による終了に対応する。

## テスト

- `moon test --target native` — コアのユニットテスト
- `tests/fetch_vendor.sh` — riscv-tests ソースの取得（SHA 固定・sha256 検証）
- `tests/build_tests.sh` — clang + lld でビルド（RISC-V GNU toolchain 不要）
- `tests/run_tests.sh <emulator>` — 60 本の pass/fail 集計

## ライセンス・出典

- riscv-tests / riscv-test-env: BSD-3-Clause（tests/VENDOR-MANIFEST.md）
- QEMU virt のメモリマップは公開仕様としてアドレス定数のみ参照
