# セッション引き継ぎ文書（ローカル Claude Code → クラウドセッション）

2026-07-25 時点のローカルセッションからの引き継ぎ。ブランチ
`feat/linux-boot` 上で busybox userspace までを実装済み。直近の
未解決事項は「未解決・要調査」を参照。

2026-07-25（同日クラウドセッション、PR #6）追記: 旧 (1) の boot
回帰 timeout を解決した。実体は 2 つの独立した不具合だった。詳細は
「解決済み（クラウドセッション）」を参照。

## 現況サマリ

- エミュレータ: RV32IMAC_Zicsr_Zifencei、M-mode + U-mode、QEMU virt
  互換マップ（UART 16550 / CLINT / PLIC / sifive_test）、spike 形式
  トレース、ELF/DTB ローダ。native CLI / js(Web) / wasm-gc の 3 系統
- Linux 6.12.97 (nommu, CONFIG_RISCV_M_MODE) がブートし、busybox
  1.36.1 の **hush** 対話シェルが動作する（uname / ps / free /
  パイプ / for ループ / /proc 読み出し / poweroff まで確認済み）
- リグレッション: moon test 22/22、wasm 4/4、riscv-tests 61/61
  （rv32uc 含む）、examples 6/6。Linux boot 回帰は musl の vfork
  修正（下記）込みで green（QEMU 検証済み、PR #6 の CI で最終確認）

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

## 解決済み（クラウドセッション 2026-07-25、PR #6）

旧 (1)「ci/test_linux_boot.sh が timeout する（exit 124）」は
2 つの独立した不具合の重なりだった:

1. **素の `poweroff` はこの userspace では電源断にならない**。
   FEATURE_SH_STANDALONE の hush は PATH の /bin/poweroff ラッパ
   より busybox applet を優先し、applet の既定動作は busybox init
   宛のシグナル送出（PID 1 が init.sh のシェルなので無効）。テスト
   は `poweroff -f`（直接 reboot(2)）を送るよう修正し、README に
   注意書きを追加した。旧テストで診断が出なかったのは `set -e` +
   `$(...)` キャプチャが timeout 時に tail を実行せず落ちるため
2. **musl 1.2.5 の riscv32 vfork() が plain fork にフォールバック
   する**（`src/process/riscv32/vfork.s` が上流に存在せず、C 版
   `clone(SIGCHLD, 0)` になる）。nommu カーネルは CLONE_VM なしの
   clone を拒否しない（kernel/fork.c の !CONFIG_MMU dup_mmap は
   exe_file を写すだけのスタブ）ため、「全メモリ共有 + 親を
   サスペンドしない」子ができ、親子が同一スタックを同時実行して
   フレームを壊し合う。タイミング依存で hush が ra=0 の 0 番地
   ジャンプ（setpgid 直後、callee-saved が多数 0）に化けていた。
   riscv64 用に上流が後から追加した vfork.s（CLONE_VM|CLONE_VFORK|
   SIGCHLD）を riscv32 として build_userspace.sh がインストール
   する形で修正。QEMU 8.2.2 (virt, -icount 含む) 上で
   - 破壊版: `clone(SIGCHLD,0)` が共有メモリ + 親非停止になる
     決定的テストで実証
   - 修正版: `vfork()` が子の exit まで親を止めることを実証、
     boot 回帰ハーネスも連続 pass
   musl 上流への報告候補（riscv32 に vfork.s がない問題）

付随してテストハーネスを整備した: 出力を見てから次の行を送る
expect 方式（fifo + ログファイル）、セッション 3 回反復（
LINUX_BOOT_ATTEMPTS で変更可）、失敗時に console tail と
ci/resolve_oops.py（vmlinux symtab による oops アドレス解決）を
CI ログへ出力する。

クラウド環境の egress 制約下でのローカル再現手段（今後の参考）:

- musl / busybox tarball は Ubuntu アーカイブの orig tarball が
  上流 sha256 と一致（pool/universe/m/musl・pool/main/b/busybox）。
  カーネルソースは GitHub の gregkh/linux ミラーから該当タグを
  shallow clone（initramfs.desc の絶対パス用に `/work` → リポジトリ
  への symlink が必要）。compiler-rt / cmake は llvm-project の
  GitHub リリース資産。ゲスト検証は qemu-system-riscv32（apt）で
  `-M virt -bios none -kernel <Image>`（vmlinux は QEMU が誤ロード
  するので `make Image` を使う）
- **moon ツールチェーンもローカル構築可能**: moonbitlang/
  moonbit-compiler の GitHub リリース `moonbit-wasm.tar.gz` に
  moonc.js（本セッション時点で pin と同一の v0.10.4+2cc641edf）と
  core が同梱される。`moon`/`moonrun` は同梱 moon_version のコミット
  を moonbitlang/moon から clone して `cargo build --release`
  （crates.io は egress 許可済み）。手順はリポジトリの install.ts
  の通り。native バックエンドのランタイム (lib/runtime.c) は
  非同梱のため native CLI は組めないが、js バックエンドは完全動作:
  `moon test --target js` が全 22 テストを、`moon build --target js
  --release web` + node ドライバ（web/api.mbt の vm_* API で
  vmlinux + dtb をロードし、バナー待ち → 入力注入）が Linux ブート
  一式をローカル実行できる（約 6 秒 / 37M steps）。wasm-gc は
  ローカル moonrun の配列上限で 128MB RAM を確保できず不可

## 未解決・要調査（優先順）

1. **busybox init アプレットが PID 1 で exit 255**（inittab の
   sysinit 実行後に死亡 → kernel panic）。現在はシェルスクリプト
   /init（linux/init.sh）で回避しており実害はないが、原因未特定。
   busybox init も子の起動に vfork を使うため、上記 vfork 修正で
   直っている可能性がある。ctrl-alt-del 等が欲しくなったら再調査
2. **userspace の NULL ジャンプ時に二次 kernel oops**
   （show_opcodes → copy_from_user_nofault → memcpy が epc-20 の
   wrap した不正アドレスを読み、nommu では extable が効かず
   "Fatal exception in interrupt" panic）。CI ログで実地確認済み
   （dump_instr → copy_from_user_nofault → memcpy+0xe4 で
   badaddr=0xffffffec）。nommu カーネル本来の挙動。実害は「ユーザ
   プロセスのクラッシュがカーネル panic に化ける」こと。init.sh で
   `echo 0 > /proc/sys/debug/exception-trace` すれば oops 印字ごと
   抑止でき、プロセスは SIGSEGV で死ぬだけになる（ただし今回の
   ような診断には oops が有用なので、既定では残している）。
   必要なら上流報告
3. LR/SC 予約をトラップ進入で無効化する修正を入れた（UP nommu では
   カーネルのスピンロックが no-op のため、古い予約がプロセス間で
   SC を誤成立させ得る）。riscv-tests 61/61 は通っているが、A 拡張
   周りで異常を見たらここを疑うこと。なお過去に見た「A 拡張周りの
   怪しい挙動」の一部は上記 vfork 競合による共有メモリ破壊だった
   可能性もある

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

- PR #6 マージ → main の pages ジョブでサイト再組立（Web の Linux
  サンプルが hush シェルになる。ci/build_site.sh は web.js の内容
  ハッシュでキャッシュバスティングする）
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
