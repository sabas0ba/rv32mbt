# linux/ のライセンス

- 本ディレクトリの全ファイル（Dockerfile / build*.sh / run.sh /
  rv32mbt.dts / rv32_nommu.config / busybox.config / init.c /
  init.sh / poweroff.sh / reboot.sh / initramfs.desc）:
  Apache-2.0（ルートの LICENSE）。いずれも本リポジトリのオリジナルで、
  上流ソースからの複製を含まない
- ビルド時取得する上流ソース（リポジトリには含まれない。いずれも
  sha256 固定、docs/toolchain.md）:
  - Linux カーネル: GPL-2.0 (with syscall exception)
  - busybox: GPL-2.0
  - musl: MIT
  - compiler-rt: Apache-2.0 WITH LLVM-exception

## 配布物の対応ソース

CI Artifacts / GitHub Pages で配布する vmlinux は GPL-2.0
（カーネル + initramfs 内の busybox）。以下から完全に再現できる。

| 項目 | 内容 |
|---|---|
| ソース | linux-6.12.97.tar.xz / busybox-1.36.1.tar.bz2 / musl-1.2.5.tar.gz / compiler-rt-18.1.3.src.tar.xz（各公式サイト、無改変・パッチなし） |
| コンフィグ | nommu_virt_defconfig + linux/rv32_nommu.config、allnoconfig + linux/busybox.config |
| 手順 | linux/Dockerfile + linux/build.sh（build_userspace.sh を内包） |
