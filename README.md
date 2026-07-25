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
3. `moon test --target wasm-gc -p .../wasm`（wasm API のテスト）
4. `moon build --target native --release cmd/main`（CLI バイナリ）
5. riscv-tests の取得・ビルド・実行（tests/ 参照、60 本）
6. サンプルプログラムのビルド・実行と期待出力の比較（tests/examples/）
7. `moon build --target js --release web`（ブラウザ用モジュール）

GitHub Actions（.github/workflows/ci.yml）は push / PR ごとに同じ
イメージをビルドして `ci/run.sh` を実行し、続けて `ci/build_dist.sh` で
生成した成果物（native CLI・wasm VM モジュール・web サイト一式）を
Artifacts として公開する。main への push では `ci/build_site.sh` で
組み立てたサイトを GitHub Pages へデプロイする（リポジトリ設定で
Pages の Source を "GitHub Actions" にしておくこと）。VS Code の
devcontainer（.devcontainer/）も同じ Dockerfile を使う。

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
| `--trace` | spike の commit log 形式の実行トレースを stderr へ出力する |

終了はゲスト側の sifive_test finisher（PASS/FAIL 書き込み）と riscv-tests
の HTIF (`tohost`) に対応し、プロセスの終了コードへ反映される（正常終了
で 0、FAIL でそのコード）。シェルスクリプトからは `$?` で合否判定できる。
tests/ の各ハーネスもこの仕組みを用いる。停止しないプログラムを与えると
実行が終わらないため、手動実行時も `--max-steps` の指定を推奨する。

`--trace` の書式は spike の commit log に準拠する（stdout の UART 出力
とは分離される）:

```
core   0: 3 0x80000000 (0x10000537) x10 0x10000000
```

レジスタ書き戻しは実行前後のレジスタファイル比較で検出するため、同値
書き込みは表示されない。メモリオペランドは記録しない。

## ブラウザフロントエンド（web/）

js backend でビルドしたエミュレータをブラウザで動かす。サンプル ELF
（hello / hello_c / fib / lifegame / mandelbrot / primes）をプルダウン
から選択するか、任意の ELF / flat binary を読み込んで実行できる。

デバッグパネルを備える:

- Run / Pause / Step / Reset と実行速度の選択（1 inst/s〜最高速）
- レジスタ（x0〜x31 + pc）と主要 CSR（mstatus / mie / mip / mtvec /
  mepc / mcause / mtval ほか、cycle / instret）の表示
- メモリダンプ（hex + ASCII、アドレス指定と PC / SP へのジャンプ）
- spike commit log 形式の実行トレース表示（ON/OFF 可）

```
bash ci/build_site.sh                       # _build/site/ に組み立て
python3 -m http.server 8000 -d _build/site  # ローカル確認
```

main ブランチの内容は GitHub Pages
（https://sabas0ba.github.io/rv32mbt/）に公開される。

## wasm モジュール（wasm/）

コア VM を wasm-gc backend でビルドしたモジュール。エクスポートは
すべて Int 引数・Int 返り値であり、GC 型のマーシャリングなしに任意の
wasm ホストから駆動できる（イメージは 1 バイトずつステージし、UART
出力も 1 バイトずつ取り出す）。step 実行、レジスタ・CSR・メモリの読み
出し、実行トレースの取得にも対応する。CI の Artifacts
（rv32mbt-vm-wasm）で配布する。

```
moon build --target wasm-gc --release wasm
# -> _build/wasm-gc/release/build/wasm/wasm.wasm
```

## テスト

- `moon test --target native` — コアのユニットテスト
- `tests/fetch_vendor.sh` — riscv-tests ソースの取得（SHA 固定・sha256 検証）
- `tests/build_tests.sh` — clang + lld でビルド（RISC-V GNU toolchain 不要）
- `tests/run_tests.sh <emulator>` — 60 本の pass/fail 集計
- `tests/examples/` — ベアメタルのサンプルプログラム。UART へ出力する
  hello（アセンブリ / C）、fib、ライフゲーム、mandelbrot（固定小数点
  ASCII 描画）、primes（エラトステネスの篩）を C ランタイム（crt0.S +
  rt.c）付きでビルドし、`run_examples.sh <emulator>` がリポジトリ内の
  .expect ファイルと出力を比較する

## ライセンス・出典

- 本プロジェクト: Apache-2.0（LICENSE）
- riscv-tests / riscv-test-env: BSD-3-Clause（tests/VENDOR-MANIFEST.md）
- QEMU virt のメモリマップは公開仕様としてアドレス定数のみ参照
