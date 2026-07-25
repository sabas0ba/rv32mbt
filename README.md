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
5. サンプルプログラムのビルド・実行と期待出力の比較（tests/examples/）
6. `moon build --target js --release web`（ブラウザ用モジュール）

GitHub Actions（.github/workflows/ci.yml）は push / PR ごとに同じ
イメージをビルドして `ci/run.sh` を実行する。VS Code の devcontainer
（.devcontainer/）も同じ Dockerfile を使う。

## CLI の使い方

ビルドすると `_build/native/release/build/cmd/main/main.exe` が生成される。

```
moon build --target native --release cmd/main
_build/native/release/build/cmd/main/main.exe [オプション] <image>

# 例: サンプルの実行
_build/native/release/build/cmd/main/main.exe tests/build/hello.elf
_build/native/release/build/cmd/main/main.exe tests/build/lifegame.elf
```

ELF32 (RV32) 実行ファイルを DRAM（0x80000000）にロードして実行する。
UART 出力は標準出力へ流れる。

| オプション | 意味 |
|---|---|
| `--quiet` | 終了時の `[rv32mbt] halted, ...` 表示を抑止する |
| `--max-steps N` | N 命令実行したら停止する（既定: 無制限） |
| `--bin` | ELF ではなく生バイナリとしてロードする |
| `--load-addr A` | `--bin` 時のロード先アドレス |
| `--pc A` | 開始 PC を指定する |

終了はゲスト側の sifive_test finisher（PASS/FAIL 書き込み）と riscv-tests
の HTIF (`tohost`) に対応し、プロセスの終了コードへ反映される（正常終了
で 0、FAIL でそのコード）。シェルスクリプトからは `$?` で合否判定できる。
tests/ の各ハーネスもこの仕組みを用いる。停止しないプログラムを与えると
実行が終わらないため、手動実行時も `--max-steps` の指定を推奨する。

## テスト

- `moon test --target native` — コアのユニットテスト
- `tests/fetch_vendor.sh` — riscv-tests ソースの取得（SHA 固定・sha256 検証）
- `tests/build_tests.sh` — clang + lld でビルド（RISC-V GNU toolchain 不要）
- `tests/run_tests.sh <emulator>` — 60 本の pass/fail 集計
- `tests/examples/` — ベアメタルのサンプルプログラム。UART へ出力する
  hello（アセンブリ / C）、fib、ライフゲームを C ランタイム（crt0.S +
  rt.c）付きでビルドし、`run_examples.sh <emulator>` がリポジトリ内の
  .expect ファイルと出力を比較する

## ライセンス・出典

- 本プロジェクト: Apache-2.0（LICENSE）
- riscv-tests / riscv-test-env: BSD-3-Clause（tests/VENDOR-MANIFEST.md）
- QEMU virt のメモリマップは公開仕様としてアドレス定数のみ参照
