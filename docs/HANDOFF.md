# セッション引き継ぎ文書

新しいCoworkセッションでこのリポジトリの作業を継続するための文書。

## 復元手順

1. このセッションに `rv32mbt-checkpoint.bundle` を添付する
2. 以下を実行:
   ```
   git clone <uploads>/rv32mbt-checkpoint.bundle ~/work/rv32mbt
   cd ~/work/rv32mbt && git log --oneline   # 6コミットあることを確認
   ```

## プロジェクト概要

- 目的: MoonBit による RV32IMA エミュレータ。QEMU virt 互換メモリマップ、
  UART 16550。ネイティブ(native backend) + ブラウザ(js backend)。
  最終目標は nommu Linux 起動。docs/design.md 参照。
- 進捗: コア実装・CLI・Web・テストハーネスは記述済みだが
  **MoonBit コンパイラ未導入のため一度もコンパイルしていない**。
  構文エラーの修正が最初の作業になる。

## 環境構築（要 egress: cli.moonbitlang.com）

```
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"
moon version --all   # バージョンを記録し docs/toolchain.md と Dockerfile に固定すること
```

- riscv クロスコンパイラは不要。導入済みの clang+lld を使用
  （tests/build_tests.sh が動作確認済み、60 ELF 生成可能）
- qemu 差分テストは apt (archive.ubuntu.com) 許可時のみ:
  `apt-get install qemu-system-misc`（バージョン固定を記録）

## ビルド・検証手順（コンパイラ導入後）

1. `moon new /tmp/probe` で生成物を確認し、moon.mod / moon.pkg の
   構文が現行ツールチェーンと一致するか検証。不一致なら本リポジトリの
   moon.mod / */moon.pkg を修正（特に web/moon.pkg の link(js(...)) は
   要確認の暫定記述）
2. `moon check` → エラーを潰す。特に不確かな点:
   - UInt/Int の演算子（`&`,`|`,`^`,`<<`,`>>`, `.lnot()`）の実在
   - `for x in a..<b { break v } nobreak { v }` の可否
   - Byte/UInt16 の `.to_int()`、`Bytes::from_array`、`StringBuilder`
   - suberror のラベル付きコンストラクタ、`try?` / `catch` 構文
3. `moon test --target native` → core のユニットテスト（10本）を通す
4. `moon build --target native --release cmd/main`
   → tests/run_tests.sh で riscv-tests 60本を実行
5. `moon build --target js --release web`
   → web/index.html の import パスを実際の出力パスに合わせる
6. ネイティブ/ブラウザ両方で tests/build/hello.elf の動作確認
7. Dockerfile（バージョン固定）と README を作成、tar で成果物送付

## 作業規約（ユーザ要件）

- Conventional Commits、機能追加は原則 branch/worktree
- 依存パッケージ追加は事前確認、バージョン固定必須
- 外部コード（GPL等）の混入禁止。riscv-tests は BSD-3 で vendor 済み
  （tests/vendor/MANIFEST.md 参照、blob SHA 検証済み）
- 比喩・誇張のない技術文書調
