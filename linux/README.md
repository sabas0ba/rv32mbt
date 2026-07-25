# linux/ のライセンス

- 本ディレクトリの全ファイル（Dockerfile / build.sh / run.sh /
  rv32mbt.dts / rv32_nommu.config / init.S / initramfs.desc）:
  Apache-2.0（ルートの LICENSE）。いずれも本リポジトリのオリジナルで、
  カーネルソースからの複製を含まない
- Linux カーネル: GPL-2.0 (with syscall exception)。ソースは
  リポジトリに含まれず、build.sh が kernel.org から取得する
  （sha256 検証、docs/toolchain.md）

## 配布物 vmlinux の対応ソース

CI Artifacts / GitHub Pages で配布する vmlinux (GPL-2.0) は
以下から再現できる。

| 項目 | 内容 |
|---|---|
| ソース | linux-6.12.97.tar.xz（kernel.org、無改変） |
| コンフィグ | nommu_virt_defconfig + linux/rv32_nommu.config |
| 手順 | linux/Dockerfile + linux/build.sh |
