# セッション引き継ぎ文書（Cowork → Claude Code）

Coworkクラウドセッションからローカルの Claude Code セッションへ作業を
引き継ぐための文書。前セッションではネットワークegress制約により
MoonBit ツールチェーンが導入できず、コードは**一度もコンパイルされて
いない**。最初の作業はビルドを通すことになる。

## 復元手順

```
cd ~/repos
git clone rv32mbt-checkpoint.bundle rv32mbt
cd rv32mbt
git log --oneline          # 8コミットあることを確認
git remote set-url origin https://github.com/sabas0ba/rv32mbt.git
git push -u origin main    # 空リポジトリ作成済み（public、後でprivate化可）
```

## プロジェクト概要

- 目的: MoonBit による RV32 エミュレータ。QEMU virt 互換メモリマップ、
  UART 16550。native backend（CLI）と js backend（ブラウザ）の両対応。
  最終目標は nommu Linux (CONFIG_RISCV_M_MODE) の起動。
- 詳細設計・段階計画・メモリマップ出典は docs/design.md 参照。
- 現況: RV32IMA+Zicsr コア、UART/CLINT/PLIC/sifive_test、ELF32ローダ、
  ユニットテスト、CLI/Webフロントエンド、riscv-testsハーネスまで記述済み。

## 環境構築

```
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"
moon version --all   # 導入バージョンを記録し docs/toolchain.md に固定内容を書くこと
```

- RISC-V クロスコンパイラは不要。clang 18 + lld で tests/ 一式がビルド
  できることを検証済み（tests/build_tests.sh、60 ELF 生成）。
  clang/lld が無い環境では apt 等で導入しバージョンを記録する。
- riscv-tests ソースは `bash tests/fetch_vendor.sh` で取得する
  （コミットSHA固定、sha256検証付き。出典は tests/VENDOR-MANIFEST.md）。
- qemu差分テストを行う場合は qemu-system-riscv32 (qemu-system-misc) を
  導入し、tests/examples/hello.elf の出力を
  `qemu-system-riscv32 -M virt -nographic -bios none -kernel hello.elf`
  と比較する。

## ビルド・検証手順（優先順）

1. `moon new /tmp/probe` の生成物と本リポジトリの moon.mod / */moon.pkg
   の構文を突き合わせる。旧形式(moon.mod.json/moon.pkg.json)しか受け
   付けない場合は変換する。特に web/moon.pkg の `link(js(...))` は
   ドキュメント未確認の暫定記述であり要修正の可能性が高い。
2. `moon check` を通す。未検証の構文リスク:
   - UInt/Int の `&` `|` `^` `<<` `>>` 演算子、`.lnot()` の実在
   - `for x in a..<b { break v } nobreak { v }`（for-in の break値）
   - Byte/UInt16 の `.to_int()`、`Bytes::from_array`、`Bytes::make`、
     `unsafe_to_char`、StringBuilder の `reset`/`write_char`
   - suberror のラベル付きコンストラクタ `Trap(cause~:Int, tval~:UInt)`、
     `try?` / `try!` / `catch` の用法
   - cmd/main/ffi.mbt の extern "c" 宣言と #borrow の要否
     （moonbit-c-binding ガイド: github.com/moonbitlang/moonbit-agent-guide）
3. `moon test --target native` で core のユニットテスト10本を通す。
   テスト中の命令エンコードは Python で機械的に検証済み（正しい前提で
   期待値を直すのではなく、まず実装側を疑うこと）。
4. `moon build --target native --release cmd/main` →
   `bash tests/fetch_vendor.sh && bash tests/build_tests.sh &&
   bash tests/run_tests.sh <emulator-binary>` で riscv-tests 60本。
5. `moon build --target js --release web` → web/index.html の import
   パスを実出力パスへ合わせ、ブラウザで tests/build/hello.elf を確認。
6. qemu差分（任意）、Dockerfile（全ツールバージョン固定）、README 整備。
7. 以降のロードマップ（design.md の段階計画）: WFI の省電力化、
   DTB 供給とブートプロトコル、nommu Linux カーネルのビルドと起動。

## 作業規約（ユーザ要件の要点）

- Conventional Commits。機能追加は branch/worktree で実施
- 依存パッケージの追加は事前確認、バージョンはSHA等で一意に固定
- 他プロジェクトのコード（特にGPL）の混入禁止。QEMUからは公開仕様と
  してのアドレス定数のみ参照済み。riscv-tests は BSD-3（検証済vendor）
- 一時ファイルは repo 内の gitignore 済みディレクトリ（_tmp/ 等）で扱う
- 文書・コメントは比喩を避けた技術文書調
- 検証重視: 各段階でユニットテスト・riscv-tests・（可能なら）qemu差分
