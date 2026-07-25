# ツールチェーン固定内容

開発・CI環境は リポジトリ直下の Dockerfile で構築する（podman/docker
いずれでも可）。GitHub Actions（.github/workflows/ci.yml）と
devcontainer（.devcontainer/devcontainer.json）も同じ Dockerfile を使う。

## 使い方

```
podman build -t rv32mbt-dev .
podman run --rm -v "$PWD:/work" rv32mbt-dev bash ci/run.sh   # 全リグレッション
podman run --rm -v "$PWD:/work" rv32mbt-dev moon check       # 個別コマンド
```

## 固定バージョン

| 項目 | 固定値 |
|---|---|
| ベースイメージ | ubuntu:24.04 @sha256:52df9b1ee71626e0088f7d400d5c6b5f7bb916f8f0c82b474289a4ece6cf3faf |
| moon | 0.1.20260713 (75c7e1f 2026-07-13) |
| moonc | v0.10.4+2cc641edf (2026-07-15) |
| moonrun | 0.1.20260713 (75c7e1f 2026-07-13) |
| clang / lld | 18.1.3 (Ubuntu 1:18.1.3-1ubuntu1, apt) |
| python3 | 3.12 (Ubuntu 24.04 apt) |

- MoonBit の配布サーバはバージョン指定URLを公開していない（403 を返す）
  ため、`binaries/latest` / `cores/core-latest.tar.gz` を取得し、
  Dockerfile 内で以下の sha256 と `moon version` の文字列一致を検証する。
  上流の latest が更新されると digest 不一致でビルドが失敗し、意図しない
  バージョン混入を防ぐ。
  - moonbit-linux-x86_64.tar.gz:
    `31b7fc5cc78657964a6d545792ecd7fb8eed51b97c7431a17458b58734303381`
  - core-latest.tar.gz:
    `03ad55b99f3e431f3cb81b4e2bb28bb98173304e4a1b18a891ea027cabba5d1c`
- apt パッケージはベースイメージの digest とビルド時点のアーカイブ内容で
  決まる。上表はビルドで実際に導入されたバージョンの記録。
- riscv-tests のソースは tests/fetch_vendor.sh がコミット SHA 固定 +
  sha256 検証付きで取得する（tests/VENDOR-MANIFEST.md 参照）。

## バージョン更新手順

1. 新しい tarball の sha256 を取得し、Dockerfile の `MOONBIT_SHA256` /
   `CORE_SHA256` と `MOON_VERSION`（またはベース digest）を更新
2. `podman build` 後、`moon version --all` の出力で本書の表を更新
3. `bash ci/run.sh` をコンテナ内で完走させてからコミット
