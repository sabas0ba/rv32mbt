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
| dtc | Ubuntu 24.04 apt (device-tree-compiler) |

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

## Linux カーネルビルド環境（linux/Dockerfile）

nommu RV32 カーネルのビルドは専用イメージ rv32mbt-linux で行う
（ベースイメージ digest は上表と同一）。クロスコンパイラは使わず
clang/LLVM（`make LLVM=-18`）でビルドする。

| 項目 | 固定値 |
|---|---|
| linux | 6.12.97 (LTS) |
| linux-6.12.97.tar.xz sha256 | `6cbddfa3bbd2229026f7cc5e48f6b7d6b46d39742de39a9257a2f490a0f45c6f` |
| 取得元 | cdn.kernel.org/pub/linux/kernel/v6.x/ |

カーネルソースはイメージに焼かず、linux/build.sh が取得・sha256 検証・
展開する（_build/kernel/ 以下、gitignore 済み）。config は
nommu_virt_defconfig + linux/rv32_nommu.config（RV32 化ほか）。

## userspace（linux/build_userspace.sh）

busybox userspace も同イメージでビルドする。ソースはビルド時取得・
sha256 固定:

| 項目 | バージョン | sha256 |
|---|---|---|
| musl | 1.2.5 | `a9a118bbe84d8764da0ea0d28b3ab3fae8477fc7e4085d90102b8596fc7c75e4` |
| busybox | 1.36.1 | `b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314` |
| compiler-rt (builtins) | 18.1.3 | `9a7df9300413696b0c4f7ff1e2729cb82aca375f35c05d698c44f26a4edf1c27` |
| llvm cmake modules | 18.1.3 | `acfecb615d41c5b1a0a31e15324994ca06f7a3f37d8958d719b20de0d217b71b` |

- rv32 用 compiler-rt builtins は Ubuntu の llvm-18 に含まれないため
  ソースからビルドする（cmake / llvm-18-dev / bzip2 を apt 追加）
- musl は clang + llvm-ar で riscv32 向けに静的ビルド
- busybox は allnoconfig + linux/busybox.config（hush、NOMMU、
  static PIE。ash は Kconfig で !NOMMU のため使用不可）
- Linux UAPI ヘッダはカーネルツリーの `make headers` から sysroot へ
  コピーする

## バージョン更新手順

1. 新しい tarball の sha256 を取得し、Dockerfile の `MOONBIT_SHA256` /
   `CORE_SHA256` と `MOON_VERSION`（またはベース digest）を更新
2. `podman build` 後、`moon version --all` の出力で本書の表を更新
3. `bash ci/run.sh` をコンテナ内で完走させてからコミット
