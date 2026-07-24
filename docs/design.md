# rv32emu-mbt 設計文書

## 目的

MoonBit による RV32 エミュレータ。最終目標は nommu Linux (CONFIG_RISCV_M_MODE) の起動。
ネイティブ実行（native backend）とブラウザ実行（js backend）の両方をサポートする。

## 段階計画

| Stage | 内容 | 検証 |
|-------|------|------|
| 1 | RV32IM + Zicsr + M-mode trap + UART(16550) | riscv-tests rv32ui/rv32um, unit test |
| 2 | A拡張 (LR/SC, AMO) + Zifencei | riscv-tests rv32ua |
| 3 | CLINT (mtime/mtimecmp/msip) + PLIC | 割り込みテスト |
| 4 | nommu Linux 起動 (DTB 供給, ブートプロトコル) | カーネルブートログ |

## ターゲット仕様 (Stage 1–2)

- ISA: RV32IM(A) Zicsr Zifencei、特権レベルは M-mode のみ（nommu Linux は
  CONFIG_RISCV_M_MODE で M-mode 動作。S-mode/MMU は実装しない）
- ハート数: 1
- エンディアン: little

## メモリマップ（QEMU virt 準拠）

出典: QEMU v8.2.2 `hw/riscv/virt.c` の `virt_memmap[]`、`include/hw/riscv/virt.h`。

| 領域 | ベース | サイズ | 備考 |
|------|--------|--------|------|
| TEST (sifive_test) | 0x0010_0000 | 0x1000 | 終了デバイス。riscv-tests / poweroff に使用 |
| CLINT | 0x0200_0000 | 0x1_0000 | msip@0x0, mtimecmp@0x4000, mtime@0xBFF8 |
| PLIC | 0x0C00_0000 | 0x60_0000 | priority@0x0, pending@0x1000, enable@0x2000(+0x80/ctx), threshold/claim@0x20_0000(+0x1000/ctx) |
| UART0 | 0x1000_0000 | 0x100 | 16550A, regshift=0, IRQ=10, clock=3.6864MHz |
| DRAM | 0x8000_0000 | 可変（既定 128 MiB） | |

- timebase: 10 MHz (`RISCV_ACLINT_DEFAULT_TIMEBASE_FREQ`)
- UART0_IRQ = 10（PLIC ソース番号）

## アーキテクチャ

```
core/                 バックエンド非依存のエミュレータ本体
  cpu.mbt             レジスタファイル, PC, ステップ実行
  decode.mbt          命令デコード
  exec_*.mbt          命令実行 (i/m/a/csr)
  csr.mbt             CSR ファイル (M-mode)
  trap.mbt            例外・割り込み処理
  bus.mbt             物理アドレスデコード
  ram.mbt             DRAM (FixedArray[Byte])
  uart.mbt            16550A モデル (入出力はコールバックで注入)
  clint.mbt           CLINT (Stage 3)
  plic.mbt            PLIC (Stage 3)
  machine.mbt         SoC 組み立て, 実行ループ
cmd/main/             native backend CLI (ELF/flat binary ロード, UART⇔stdio)
web/                  js backend + ブラウザページ (UART⇔DOM)
tests/                riscv-tests ランナー, ベアメタルサンプル
```

### 設計上の要点

- コアは I/O を直接行わない。UART の TX/RX はコールバック
  （`(Byte) -> Unit` / `() -> Int`）として注入し、native/js 両対応とする。
- メモリは `FixedArray[Byte]` によるフラット配列。ロード/ストアはリトル
  エンディアンで合成する。
- 命令実行は「フェッチ→デコード→実行」の関数型ループ。デコード結果は
  enum で表現し、実行は match で分岐する。
- トラップは MoonBit の例外ではなく戻り値（`StepResult`）で表現する。
- CSR: mstatus, misa, mie, mip, mtvec, mscratch, mepc, mcause, mtval,
  mhartid, mcycle(h), minstret(h), mvendorid/marchid/mimpid ほか。
  time CSR は提供しない（CLINT の mtime を使用。rdtime はトラップさせず
  mtime を返す実装とする余地あり。Stage 3 で確定）。

## 検証方針

- riscv-tests (rv32ui-p-*, rv32um-p-*, 後に rv32ua-p-*) を clang+lld で
  ビルドし、tohost 経由の pass/fail を CI で判定する。
- MoonBit unit test（デコーダ・ALU・CSR・UART レジスタ単位）。
- 参照ツールチェーンのバージョンは Dockerfile で固定する。

## 使用しない実装・知財上の注意

- 他エミュレータのコード（QEMU 等 GPL コード）は移植しない。QEMU からは
  公開仕様としてのアドレスマップ定数のみ参照する。
- 仕様の一次情報: RISC-V Unprivileged/Privileged ISA 仕様, 16550 UART
  データシート互換仕様, SiFive CLINT/PLIC 仕様。
