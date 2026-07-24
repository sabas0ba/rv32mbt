#!/usr/bin/env bash
# Fetch the pinned riscv-tests / riscv-test-env sources into tests/vendor/
# and verify them against tests/vendor.sha256.
#
# Sources (see tests/VENDOR-MANIFEST.md, kept in git):
#   riscv-software-src/riscv-tests @ RT_SHA (BSD-3-Clause)
#   riscv/riscv-test-env           @ ENV_SHA (BSD-3-Clause)
# riscv-tests' env/ is a git submodule pointing at riscv-test-env, so
# vendor/riscv-tests/env/encoding.h is fetched from riscv-test-env.
set -euo pipefail
cd "$(dirname "$0")"

RT_SHA=34e6b6d1e7936b526075432fb730d89148623484
ENV_SHA=a1c373ec89a3500630bafabf406108a8fc568bcc
RAW=https://raw.githubusercontent.com

fetch() { # fetch <url> <dest>
  mkdir -p "$(dirname "$2")"
  curl -fsSL --retry 3 -o "$2" "$1"
}

RT_FILES=(
  LICENSE
  isa/macros/scalar/test_macros.h
  isa/rv32ua/amoadd_w.S
  isa/rv32ua/amoand_w.S
  isa/rv32ua/amomax_w.S
  isa/rv32ua/amomaxu_w.S
  isa/rv32ua/amomin_w.S
  isa/rv32ua/amominu_w.S
  isa/rv32ua/amoor_w.S
  isa/rv32ua/amoswap_w.S
  isa/rv32ua/amoxor_w.S
  isa/rv32ua/lrsc.S
  isa/rv32ui/add.S
  isa/rv32ui/addi.S
  isa/rv32ui/and.S
  isa/rv32ui/andi.S
  isa/rv32ui/auipc.S
  isa/rv32ui/beq.S
  isa/rv32ui/bge.S
  isa/rv32ui/bgeu.S
  isa/rv32ui/blt.S
  isa/rv32ui/bltu.S
  isa/rv32ui/bne.S
  isa/rv32ui/fence_i.S
  isa/rv32ui/jal.S
  isa/rv32ui/jalr.S
  isa/rv32ui/lb.S
  isa/rv32ui/lbu.S
  isa/rv32ui/ld_st.S
  isa/rv32ui/lh.S
  isa/rv32ui/lhu.S
  isa/rv32ui/lui.S
  isa/rv32ui/lw.S
  isa/rv32ui/ma_data.S
  isa/rv32ui/or.S
  isa/rv32ui/ori.S
  isa/rv32ui/sb.S
  isa/rv32ui/sh.S
  isa/rv32ui/simple.S
  isa/rv32ui/sll.S
  isa/rv32ui/slli.S
  isa/rv32ui/slt.S
  isa/rv32ui/slti.S
  isa/rv32ui/sltiu.S
  isa/rv32ui/sltu.S
  isa/rv32ui/sra.S
  isa/rv32ui/srai.S
  isa/rv32ui/srl.S
  isa/rv32ui/srli.S
  isa/rv32ui/st_ld.S
  isa/rv32ui/sub.S
  isa/rv32ui/sw.S
  isa/rv32ui/xor.S
  isa/rv32ui/xori.S
  isa/rv32um/div.S
  isa/rv32um/divu.S
  isa/rv32um/mul.S
  isa/rv32um/mulh.S
  isa/rv32um/mulhsu.S
  isa/rv32um/mulhu.S
  isa/rv32um/rem.S
  isa/rv32um/remu.S
  isa/rv64ua/amoadd_d.S
  isa/rv64ua/amoadd_w.S
  isa/rv64ua/amoand_d.S
  isa/rv64ua/amoand_w.S
  isa/rv64ua/amomax_d.S
  isa/rv64ua/amomax_w.S
  isa/rv64ua/amomaxu_d.S
  isa/rv64ua/amomaxu_w.S
  isa/rv64ua/amomin_d.S
  isa/rv64ua/amomin_w.S
  isa/rv64ua/amominu_d.S
  isa/rv64ua/amominu_w.S
  isa/rv64ua/amoor_d.S
  isa/rv64ua/amoor_w.S
  isa/rv64ua/amoswap_d.S
  isa/rv64ua/amoswap_w.S
  isa/rv64ua/amoxor_d.S
  isa/rv64ua/amoxor_w.S
  isa/rv64ua/lrsc.S
  isa/rv64ui/add.S
  isa/rv64ui/addi.S
  isa/rv64ui/addiw.S
  isa/rv64ui/addw.S
  isa/rv64ui/and.S
  isa/rv64ui/andi.S
  isa/rv64ui/auipc.S
  isa/rv64ui/beq.S
  isa/rv64ui/bge.S
  isa/rv64ui/bgeu.S
  isa/rv64ui/blt.S
  isa/rv64ui/bltu.S
  isa/rv64ui/bne.S
  isa/rv64ui/fence_i.S
  isa/rv64ui/jal.S
  isa/rv64ui/jalr.S
  isa/rv64ui/lb.S
  isa/rv64ui/lbu.S
  isa/rv64ui/ld.S
  isa/rv64ui/ld_st.S
  isa/rv64ui/lh.S
  isa/rv64ui/lhu.S
  isa/rv64ui/lui.S
  isa/rv64ui/lw.S
  isa/rv64ui/lwu.S
  isa/rv64ui/ma_data.S
  isa/rv64ui/or.S
  isa/rv64ui/ori.S
  isa/rv64ui/sb.S
  isa/rv64ui/sd.S
  isa/rv64ui/sh.S
  isa/rv64ui/simple.S
  isa/rv64ui/sll.S
  isa/rv64ui/slli.S
  isa/rv64ui/slliw.S
  isa/rv64ui/sllw.S
  isa/rv64ui/slt.S
  isa/rv64ui/slti.S
  isa/rv64ui/sltiu.S
  isa/rv64ui/sltu.S
  isa/rv64ui/sra.S
  isa/rv64ui/srai.S
  isa/rv64ui/sraiw.S
  isa/rv64ui/sraw.S
  isa/rv64ui/srl.S
  isa/rv64ui/srli.S
  isa/rv64ui/srliw.S
  isa/rv64ui/srlw.S
  isa/rv64ui/st_ld.S
  isa/rv64ui/sub.S
  isa/rv64ui/subw.S
  isa/rv64ui/sw.S
  isa/rv64ui/xor.S
  isa/rv64ui/xori.S
  isa/rv64um/div.S
  isa/rv64um/divu.S
  isa/rv64um/divuw.S
  isa/rv64um/divw.S
  isa/rv64um/mul.S
  isa/rv64um/mulh.S
  isa/rv64um/mulhsu.S
  isa/rv64um/mulhu.S
  isa/rv64um/mulw.S
  isa/rv64um/rem.S
  isa/rv64um/remu.S
  isa/rv64um/remuw.S
  isa/rv64um/remw.S
)

ENV_FILES=(
  LICENSE
  encoding.h
  p/link.ld
  p/riscv_test.h
)

for f in "${RT_FILES[@]}"; do
  fetch "$RAW/riscv-software-src/riscv-tests/$RT_SHA/$f" "vendor/riscv-tests/$f"
done
fetch "$RAW/riscv/riscv-test-env/$ENV_SHA/encoding.h" "vendor/riscv-tests/env/encoding.h"
for f in "${ENV_FILES[@]}"; do
  fetch "$RAW/riscv/riscv-test-env/$ENV_SHA/$f" "vendor/riscv-test-env/$f"
done

sha256sum -c vendor.sha256 --quiet
echo "vendor: $((${#RT_FILES[@]} + ${#ENV_FILES[@]} + 1)) files fetched and verified"
