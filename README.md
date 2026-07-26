# rv32mbt

[![CI](https://github.com/sabas0ba/rv32mbt/actions/workflows/ci.yml/badge.svg)](https://github.com/sabas0ba/rv32mbt/actions/workflows/ci.yml)

MoonBit による RV32IMAC エミュレータ。QEMU virt 互換のメモリマップ
（UART 16550 / CLINT / PLIC / sifive_test）を実装し、native backend の
CLI と js backend のブラウザフロントエンドの両方で動作する。最終目標は
nommu Linux (CONFIG_RISCV_M_MODE) の起動。設計と段階計画は
docs/design.md を参照。

## 開発環境

ツールチェーンは Dockerfile で固定する（詳細は docs/toolchain.md）。
podman / docker のどちらでも動作し、VS Code の devcontainer
（.devcontainer/）も同じイメージを使う。

```
podman build -t rv32mbt-dev .
podman run --rm -v "$PWD:/work" rv32mbt-dev bash ci/run.sh
```

`ci/run.sh` の実行内容:

1. `moon check`
2. `moon test --target native`（コアのユニットテスト）
3. `moon test --target wasm-gc -p .../wasm`（wasm API のテスト）
4. `moon build --target native --release cmd/main`（CLI バイナリ）
5. riscv-tests の取得・ビルド・実行（tests/ 参照、61 本）
6. サンプルプログラムのビルド・実行と期待出力の比較（tests/examples/）
7. `moon build --target js --release web`（ブラウザ用モジュール）

## CI

GitHub Actions（.github/workflows/ci.yml）は push / PR ごとに上記
イメージで `ci/run.sh` を実行し、`ci/build_dist.sh` の成果物
（native CLI・wasm VM モジュール・web サイト一式）を Artifacts として
公開する。main への push ではさらに `ci/build_site.sh` で組み立てた
サイトを GitHub Pages へデプロイする（Pages の Source は
"GitHub Actions" に設定しておくこと）。

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

端末から実行した場合、標準入力は raw モード（ICANON / ECHO に加え
ISIG / IXON も解除）で UART0 の RX に渡される。Ctrl-C や Ctrl-S を
ホスト側の tty に横取りさせず、ゲストの行規律へ届けるため。
エミュレータ自身の操作には QEMU と同じ Ctrl-A のエスケープを使う:

| キー | 動作 |
|---|---|
| `Ctrl-A` `x` | エミュレータを終了する（端末は復元される） |
| `Ctrl-A` `a` | ゲストへ本物の Ctrl-A を送る |

パイプやファイルから入力した場合はエスケープ処理を行わず、全バイトを
そのままゲストへ渡す。

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
で 0、FAIL でそのコード）。tests/ の各ハーネスもこの仕組みで合否判定
する。停止しないプログラムを与えると実行が終わらないため、手動実行時は
`--max-steps` の指定を推奨する。

`--trace` の書式は spike の commit log に準拠する（stdout の UART 出力
とは分離される）:

```
core   0: 3 0x80000000 (0x10000537) x10 0x10000000
```

レジスタ書き戻しは実行前後のレジスタファイル比較で検出するため、同値
書き込みは表示されない。メモリオペランドは記録しない。

## Linux の起動（linux/）

nommu Linux (CONFIG_RISCV_M_MODE) が起動する。カーネルは専用の
コンテナでビルドする（Linux 6.12.97 LTS、sha256 固定、clang/LLVM。
詳細は docs/toolchain.md）:

```
podman build -t rv32mbt-linux -f linux/Dockerfile linux
podman run --rm -v "$PWD:/work" -v rv32mbt-kernel:/kernel \
    -e KERNEL_WORKDIR=/kernel rv32mbt-linux bash linux/build.sh
```

`-v rv32mbt-kernel:/kernel -e KERNEL_WORKDIR=/kernel` は Windows ホスト
向けの高速化（ソース・ビルドツリーを named volume に置く）で、Linux
ホストでは省略できる。成果物は `_build/kernel/vmlinux` と
`_build/kernel/rv32mbt.dtb` に出る。起動:

```
bash linux/run.sh            # = rv32mbt --dtb rv32mbt.dtb vmlinux
```

userspace は busybox 1.36.1（musl 1.2.5、static PIE、ELF FDPIC で
ロード）。PID 1 は busybox init（/init → busybox の symlink）で、
/etc/inittab に従って sysinit（linux/rcS が /proc・/sys・/dev を
マウントし、`busybox --install -s` で applet のシンボリックリンクを
/bin・/sbin に展開する）を実行し、コンソールに対話シェル（hush。
busybox の ash は nommu 非対応）を respawn する。ls / ps / free /
grep / sed / find / vi / less / top などの applet、パイプ、制御構文
が使える。/dev は devtmpfs（initramfs のみの構成では
CONFIG_DEVTMPFS_MOUNT が効かないため rcS で明示的にマウントする）。`poweroff` は init のシグナル
プロトコルで shutdown エントリを実行してから reboot(2) →
syscon-poweroff → sifive_test finisher と伝わり、エミュレータが
正常終了する。`reboot` は sifive_test のリセット要求（0x7777）で
エミュレータがウォームリセット（RAM クリア + ブートイメージ再ロード
+ デバイス/CSR 初期化）を行い、ゲストが再起動する。
`/opt/examples` には tests/examples/ のサンプルを musl にリンクした
Linux 版が入っており、busybox 以外のユーザ空間プログラムが動くこと
を確認できる（例: `/opt/examples/mandelbrot`）。

`/opt/nested` はエミュレータ自身をゲスト内で動かす一式（tools/wasmrun/）:

```
/opt/nested/wasmrun /opt/nested/rv32mbt.wasm /opt/nested/hello.elf 2 2000000
```

rv32mbt → Linux → wasmrun → rv32mbt(wasm) → hello.elf という入れ子に
なる。中身のエミュレータは linear-memory wasm ターゲットでビルドした
コア（ブラウザ用の wasm-gc 版は GC 対応ホストが要るため別ビルド）で、
wasmrun はそれを動かすためだけの小さな wasm インタプリタ。libc 不要の最小シェルも /bin/mini に残している。userspace のビルドは linux/build.sh が
linux/build_userspace.sh 経由で行う（musl / busybox / compiler-rt
builtins をビルド時取得・sha256 固定。docs/toolchain.md 参照）。
ライセンス（GPL-2.0 の対応ソース明示を含む）は linux/README.md 参照。

## ブラウザフロントエンド（web/）

js backend でビルドしたエミュレータをブラウザで動かす。既定のサンプル
は Linux カーネルブート（vmlinux + DTB）で、そのほかのサンプル ELF
（hello / hello_c / fib / lifegame / mandelbrot / primes）や任意の
ELF / flat binary も選択できる。Linux サンプルをローカルで表示するには
事前に linux/build.sh でカーネルをビルドしておく（無い場合は他の
サンプルのみ動作）。

デバッグパネルの機能:

- Run / Pause / Step / Reset と実行速度の選択（1 inst/s〜最高速）
- レジスタ（x0〜x31 + pc）と主要 CSR（mstatus / mie / mip / mtvec /
  mepc / mcause / mtval ほか、cycle / instret）の表示
- メモリダンプ（hex + ASCII、アドレス指定と PC / SP へのジャンプ）
- spike commit log 形式の実行トレース表示（ON/OFF 可）
- ターミナル入力はモバイルのソフトウェアキーボード / IME にも対応
  （タップで入力開始）。Esc / Tab / 矢印 / ^C / ^D はソフトキーから
  送信できる

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
出力も 1 バイトずつ取り出す）。step 実行、レジスタ・CSR・メモリの
読み出し、実行トレースの取得に対応する。CI の Artifacts
（rv32mbt-vm-wasm）で配布する。

```
moon build --target wasm-gc --release wasm
# -> _build/wasm-gc/release/build/wasm/wasm.wasm
```

## テスト

- `moon test --target native` — コアのユニットテスト
- `tests/fetch_vendor.sh` — riscv-tests ソースの取得（SHA 固定・sha256 検証）
- `tests/build_tests.sh` — clang + lld でビルド（RISC-V GNU toolchain 不要）
- `tests/run_tests.sh <emulator>` — 61 本の pass/fail 集計
- `tests/examples/` — サンプルプログラム。UART へ出力する
  hello（アセンブリ / C）、fib、ライフゲーム、mandelbrot（固定小数点
  ASCII 描画）、primes（エラトステネスの篩）を C ランタイム（crt0.S +
  rt.c）付きでベアメタル向けにビルドし、`run_examples.sh <emulator>`
  がリポジトリ内の .expect ファイルと出力を比較する。
  `build_linux.sh` は同じソースを musl（stdlib）にリンクして Linux
  ユーザ空間向けにもビルドし、initramfs の /opt/examples へ入れる
  （sample.h が `__linux__` で stdio に切り替わるだけなので出力は
  ベアメタル版とバイト単位で同一。同じ .expect で検証できる）
- `tools/wasmrun/` — 整数のみの wasm サブセットを解釈する小さな
  インタプリタ（浮動小数点なし、72 命令 + memory.copy/fill）。
  エミュレータコアの wasm モジュールを実行するためのもので、
  `CC_HOST=1 bash tools/wasmrun/build.sh` でホスト版も作れる
- `ci/test_linux_boot.sh` — Linux ブート回帰。カーネルをブートして
  対話シェルに uname / /opt/examples の各サンプル（出力を md5sum で
  .expect と照合）/ 入れ子エミュレータ（/opt/nested、出力を
  hello.expect と照合）/ reboot（ウォームリセット後の再ブート含む）/
  poweroff を流し、期待マーカーと正常終了を検査する。ci/run.sh からは `RUN_LINUX_BOOT`（auto / 1 / 0、既定 auto =
  カーネル成果物がある場合のみ実行）で切り替える。CI では成果物を
  actions/cache（キー: linux/** のハッシュ）で再利用し、必須で実行する

## ライセンス・出典

- 本プロジェクト: Apache-2.0（LICENSE）
- riscv-tests / riscv-test-env: BSD-3-Clause（tests/VENDOR-MANIFEST.md）
- QEMU virt のメモリマップは公開仕様としてアドレス定数のみ参照
- Linux カーネル: GPL-2.0。ソースはリポジトリに含まれず、ビルド時に
  kernel.org から取得する。配布される vmlinux の対応ソースと詳細は
  linux/README.md を参照
