# セッション引き継ぎ文書（ローカル Claude Code → クラウドセッション）

2026-07-25 時点のローカルセッションからの引き継ぎ。ブランチ
`feat/linux-boot` 上で busybox userspace までを実装済み。直近の
未解決事項は「未解決・要調査」を参照。

## 現況サマリ

- エミュレータ: RV32IMAC_Zicsr_Zifencei、M-mode + U-mode、QEMU virt
  互換マップ（UART 16550 / CLINT / PLIC / sifive_test）、spike 形式
  トレース、ELF/DTB ローダ。native CLI / js(Web) / wasm-gc の 3 系統
- Linux 6.12.97 (nommu, CONFIG_RISCV_M_MODE) がブートし、busybox
  1.36.1 の **hush** 対話シェルが動作する（uname / ps / free /
  パイプ / for ループ / /proc 読み出し / poweroff まで確認済み）
- リグレッション: moon test 22/22、wasm 4/4、riscv-tests 61/61
  （rv32uc 含む）、examples 6/6。Linux boot 回帰は下記 (1) の理由で
  現在 red

## ビルド・実行（Linux ホスト / クラウド）

コンテナは 2 つ（リポジトリ直下と linux/ の Dockerfile）。クラウドの
Linux 環境ではバインドマウントの性能問題がないため named volume や
KERNEL_WORKDIR は不要:

```
docker build -t rv32mbt-dev .
docker build -t rv32mbt-linux -f linux/Dockerfile linux
docker run --rm -v "$PWD:/work" rv32mbt-linux bash linux/build.sh
docker run --rm -v "$PWD:/work" rv32mbt-dev bash ci/run.sh        # 回帰
docker run --rm -it -v "$PWD:/work" rv32mbt-dev bash linux/run.sh # 対話ブート
```

- 全上流ソース（moon / kernel / musl / busybox / compiler-rt /
  riscv-tests）はビルド時取得・sha256 固定（docs/toolchain.md）。
  egress 制約がある場合は tarball を _build/kernel/ と
  _build/kernel/userspace/ に事前配置すれば fetch はスキップされる
- Windows ホスト固有の注意（named volume、Git Bash の MSYS パス変換）
  は README と本文書の対象外。クラウドでは該当しない

## 未解決・要調査（優先順）

1. **ci/test_linux_boot.sh が timeout する（exit 124）**。busybox
   (hush) 構成へ更新した直後から。同一入力の手動実行
   （`printf 'uname -a\npoweroff\n' | bash linux/run.sh ...`）は約
   30 秒で完走するため、テストスクリプト側の問題の可能性が高い
   （`$(...)` キャプチャ下での挙動、stdin EOF 後の入力ゲート
   （cmd/main の rx_listening 保留）との相互作用などを疑う）。
   これを直して RUN_LINUX_BOOT=1 の CI green を確認するのが最初の
   作業
2. **busybox init アプレットが PID 1 で exit 255**（inittab の
   sysinit 実行後に死亡 → kernel panic）。現在はシェルスクリプト
   /init（linux/init.sh）で回避しており実害はないが、原因未特定。
   ctrl-alt-del 等が欲しくなったら再調査
3. **userspace の NULL ジャンプ時に二次 kernel oops**
   （show_opcodes → copy_from_user_nofault → memcpy が epc-20 の
   wrap した不正アドレスを読み、nommu では extable が効かず
   "Fatal exception in interrupt" panic）。nommu カーネル本来の
   挙動と推定（QEMU でも再現するはず）。実害は「ユーザプロセスの
   クラッシュがカーネル panic に化ける」こと。余裕があれば QEMU で
   裏取りし、必要なら上流報告
4. LR/SC 予約をトラップ進入で無効化する修正を入れた（UP nommu では
   カーネルのスピンロックが no-op のため、古い予約がプロセス間で
   SC を誤成立させ得る）。riscv-tests 61/61 は通っているが、A 拡張
   周りで異常を見たらここを疑うこと

## 主要な設計メモ（今回分）

- busybox の ash は Kconfig で !NOMMU のため使えない。シェルは
  hush（NOMMU 対応）。applet 解決は FEATURE_SH_STANDALONE +
  /proc/self/exe の再 exec に依存するため、**/proc マウント前に
  外部コマンドを実行してはならない**（init.sh 冒頭でマウント）
- busybox の .config は allnoconfig に linux/busybox.config を
  マージして生成（busybox の古い kconfig は再定義を無視するため、
  build_userspace.sh が既存行を削除してから追記する）
- clang では busybox の `ptr_to_globals`（const 宣言 + 非 const
  経由代入）が定数畳み込みで壊れる。`CONFIG_EXTRA_CFLAGS=
  "-DBB_GLOBAL_CONST="` で無効化済み（libbb.h 公認の回避策）
- static PIE は再配置ゼロが理想だが、busybox は R_RISCV_RELATIVE を
  持ち musl の rcrt1 が自己再配置する。/init 用の最小 init
  （linux/init.c → /bin/mini）は再配置ゼロを build.sh が検査する
- rv32 用 compiler-rt builtins は Ubuntu llvm-18 に無いため
  ソースビルド（クロス libgcc 相当。crtbegin/crtend も同梱し、
  cc ラッパーが -resource-dir で参照）

## 次の候補作業

- (1) を解消して CI green 化、サイト再組立（Web の Linux サンプルが
  hush シェルになる。ci/build_site.sh は web.js の内容ハッシュで
  キャッシュバスティングする）
- busybox applet の拡充とシンボリックリンク群の整備（現状の PATH
  解決は hush の SH_STANDALONE 頼み）
- ブートオプションは CONFIG_CMDLINE_EXTEND 構成のため、DTS の
  chosen/bootargs 追記 + dtc 再実行だけで rdinit= 等を変更できる
  （カーネル再ビルド不要。デバッグに便利）
- 長期: SMP はスコープ外、S-mode/MMU は design.md の通り非対応方針

## 参照

- 設計・段階計画: docs/design.md（Stage 1–6 実装済みと記録）
- ツールチェーン固定: docs/toolchain.md
- linux/ のライセンスと配布物の対応ソース: linux/README.md
- 作業規約: リポジトリ直下 CLAUDE.md（Conventional Commits、
  依存追加は事前確認、push はユーザが実施、等）
