///|
/// Sign-extend the low `bits` bits of `x`.
fn sext(x : UInt, bits : Int) -> UInt {
  let sh = 32 - bits
  ((x.reinterpret_as_int() << sh) >> sh).reinterpret_as_uint()
}

///|
fn imm_i(inst : UInt) -> UInt {
  sext(inst >> 20, 12)
}

///|
fn imm_s(inst : UInt) -> UInt {
  sext(((inst >> 25) << 5) | ((inst >> 7) & 0x1F), 12)
}

///|
fn imm_b(inst : UInt) -> UInt {
  sext(
    ((inst >> 31) << 12) |
    (((inst >> 7) & 0x1) << 11) |
    (((inst >> 25) & 0x3F) << 5) |
    (((inst >> 8) & 0xF) << 1),
    13,
  )
}

///|
fn imm_u(inst : UInt) -> UInt {
  inst & 0xFFFFF000
}

///|
fn imm_j(inst : UInt) -> UInt {
  sext(
    ((inst >> 31) << 20) |
    (((inst >> 12) & 0xFF) << 12) |
    (((inst >> 20) & 0x1) << 11) |
    (((inst >> 21) & 0x3FF) << 1),
    21,
  )
}

///|
fn illegal(inst : UInt) -> Trap {
  Trap(cause=CAUSE_ILLEGAL_INSTRUCTION, tval=inst)
}

///|
/// Decode and execute one 32-bit instruction. Updates pc.
fn Machine::execute(self : Machine, inst : UInt) -> Unit raise Trap {
  let opcode = (inst & 0x7F).reinterpret_as_int()
  let rd = ((inst >> 7) & 0x1F).reinterpret_as_int()
  let rs1 = ((inst >> 15) & 0x1F).reinterpret_as_int()
  let rs2 = ((inst >> 20) & 0x1F).reinterpret_as_int()
  let funct3 = ((inst >> 12) & 0x7).reinterpret_as_int()
  let funct7 = ((inst >> 25) & 0x7F).reinterpret_as_int()
  let next = self.pc + 4
  match opcode {
    // LUI
    0x37 => {
      self.rset(rd, imm_u(inst))
      self.pc = next
    }
    // AUIPC
    0x17 => {
      self.rset(rd, self.pc + imm_u(inst))
      self.pc = next
    }
    // JAL
    0x6F => {
      let target = self.pc + imm_j(inst)
      if (target & 0x3) != 0 {
        raise Trap(cause=CAUSE_MISALIGNED_FETCH, tval=target)
      }
      self.rset(rd, next)
      self.pc = target
    }
    // JALR
    0x67 => {
      if funct3 != 0 {
        raise illegal(inst)
      }
      let target = (self.rget(rs1) + imm_i(inst)) & 0xFFFFFFFE
      if (target & 0x3) != 0 {
        raise Trap(cause=CAUSE_MISALIGNED_FETCH, tval=target)
      }
      self.rset(rd, next)
      self.pc = target
    }
    // BRANCH
    0x63 => {
      let a = self.rget(rs1)
      let b = self.rget(rs2)
      let taken = match funct3 {
        0 => a == b // BEQ
        1 => a != b // BNE
        4 => a.reinterpret_as_int() < b.reinterpret_as_int() // BLT
        5 => a.reinterpret_as_int() >= b.reinterpret_as_int() // BGE
        6 => a < b // BLTU
        7 => a >= b // BGEU
        _ => raise illegal(inst)
      }
      if taken {
        let target = self.pc + imm_b(inst)
        if (target & 0x3) != 0 {
          raise Trap(cause=CAUSE_MISALIGNED_FETCH, tval=target)
        }
        self.pc = target
      } else {
        self.pc = next
      }
    }
    // LOAD
    0x03 => {
      let addr = self.rget(rs1) + imm_i(inst)
      let v = match funct3 {
        0 => sext(self.load8(addr), 8) // LB
        1 => sext(self.load16(addr), 16) // LH
        2 => self.load32(addr) // LW
        4 => self.load8(addr) // LBU
        5 => self.load16(addr) // LHU
        _ => raise illegal(inst)
      }
      self.rset(rd, v)
      self.pc = next
    }
    // STORE
    0x23 => {
      let addr = self.rget(rs1) + imm_s(inst)
      let v = self.rget(rs2)
      match funct3 {
        0 => self.store8(addr, v)
        1 => self.store16(addr, v)
        2 => self.store32(addr, v)
        _ => raise illegal(inst)
      }
      self.pc = next
    }
    // OP-IMM
    0x13 => {
      let a = self.rget(rs1)
      let imm = imm_i(inst)
      let shamt = ((inst >> 20) & 0x1F).reinterpret_as_int()
      let v = match funct3 {
        0 => a + imm // ADDI
        1 => {
          if funct7 != 0 {
            raise illegal(inst)
          }
          a << shamt // SLLI
        }
        2 =>
          if a.reinterpret_as_int() < imm.reinterpret_as_int() {
            1
          } else {
            0
          } // SLTI
        3 => if a < imm { 1 } else { 0 } // SLTIU
        4 => a ^ imm // XORI
        5 =>
          match funct7 {
            0x00 => a >> shamt // SRLI
            0x20 =>
              (a.reinterpret_as_int() >> shamt).reinterpret_as_uint() // SRAI
            _ => raise illegal(inst)
          }
        6 => a | imm // ORI
        7 => a & imm // ANDI
        _ => raise illegal(inst)
      }
      self.rset(rd, v)
      self.pc = next
    }
    // OP
    0x33 => {
      let a = self.rget(rs1)
      let b = self.rget(rs2)
      let v = match funct7 {
        0x00 =>
          match funct3 {
            0 => a + b // ADD
            1 => a << (b.reinterpret_as_int() & 0x1F) // SLL
            2 =>
              if a.reinterpret_as_int() < b.reinterpret_as_int() {
                1
              } else {
                0
              } // SLT
            3 => if a < b { 1 } else { 0 } // SLTU
            4 => a ^ b // XOR
            5 => a >> (b.reinterpret_as_int() & 0x1F) // SRL
            6 => a | b // OR
            7 => a & b // AND
            _ => raise illegal(inst)
          }
        0x20 =>
          match funct3 {
            0 => a - b // SUB
            5 =>
              (a.reinterpret_as_int() >> (b.reinterpret_as_int() & 0x1F)).reinterpret_as_uint() // SRA
            _ => raise illegal(inst)
          }
        0x01 => self.exec_m(funct3, a, b) // RV32M
        _ => raise illegal(inst)
      }
      self.rset(rd, v)
      self.pc = next
    }
    // MISC-MEM: FENCE / FENCE.I
    0x0F => {
      match funct3 {
        0 => () // FENCE: no-op on a single in-order hart
        1 => () // FENCE.I: no instruction cache to flush
        _ => raise illegal(inst)
      }
      self.pc = next
    }
    // SYSTEM
    0x73 => self.exec_system(inst, rd, rs1, funct3)
    // AMO (RV32A)
    0x2F => {
      if funct3 != 2 {
        raise illegal(inst)
      }
      self.exec_amo(inst, rd, rs1, rs2, funct7)
      self.pc = next
    }
    _ => raise illegal(inst)
  }
}

///|
/// RV32M: MUL/DIV group (funct7 = 0x01).
fn Machine::exec_m(self : Machine, funct3 : Int, a : UInt, b : UInt) -> UInt raise Trap {
  ignore(self)
  let ai = a.reinterpret_as_int()
  let bi = b.reinterpret_as_int()
  match funct3 {
    0 => (ai * bi).reinterpret_as_uint() // MUL
    1 =>
      ((ai.to_int64() * bi.to_int64()) >> 32).to_int().reinterpret_as_uint() // MULH
    2 =>
      ((ai.to_int64() * b.to_uint64().reinterpret_as_int64()) >> 32)
      .to_int()
      .reinterpret_as_uint() // MULHSU
    3 => ((a.to_uint64() * b.to_uint64()) >> 32).to_uint() // MULHU
    4 =>
      // DIV
      if bi == 0 {
        0xFFFFFFFF
      } else if ai == -2147483648 && bi == -1 {
        a
      } else {
        (ai / bi).reinterpret_as_uint()
      }
    5 => if b == 0 { 0xFFFFFFFF } else { a / b } // DIVU
    6 =>
      // REM
      if bi == 0 {
        a
      } else if ai == -2147483648 && bi == -1 {
        0
      } else {
        (ai % bi).reinterpret_as_uint()
      }
    7 => if b == 0 { a } else { a % b } // REMU
    _ => raise Trap(cause=CAUSE_ILLEGAL_INSTRUCTION, tval=0)
  }
}

///|
/// RV32A: LR/SC and AMO. Operates on DRAM only.
fn Machine::exec_amo(self : Machine, inst : UInt, rd : Int, rs1 : Int, rs2 : Int, funct7 : Int) -> Unit raise Trap {
  let funct5 = funct7 >> 2
  let addr = self.rget(rs1)
  let is_lr = funct5 == 0x02
  if (addr & 0x3) != 0 {
    raise Trap(
      cause=if is_lr { CAUSE_MISALIGNED_LOAD } else { CAUSE_MISALIGNED_STORE },
      tval=addr,
    )
  }
  let off = match self.ram_off(addr, 4) {
    Some(off) => off
    None =>
      raise Trap(
        cause=if is_lr { CAUSE_LOAD_ACCESS } else { CAUSE_STORE_ACCESS },
        tval=addr,
      )
  }
  match funct5 {
    // LR.W
    0x02 => {
      if rs2 != 0 {
        raise illegal(inst)
      }
      self.reservation = off
      self.rset(rd, self.ram.read32(off))
    }
    // SC.W
    0x03 => {
      if self.reservation == off {
        self.ram.write32(off, self.rget(rs2))
        self.rset(rd, 0)
      } else {
        self.rset(rd, 1)
      }
      self.reservation = -1
    }
    _ => {
      let old = self.ram.read32(off)
      let src = self.rget(rs2)
      let nv = match funct5 {
        0x01 => src // AMOSWAP.W
        0x00 => old + src // AMOADD.W
        0x04 => old ^ src // AMOXOR.W
        0x0C => old & src // AMOAND.W
        0x08 => old | src // AMOOR.W
        0x10 =>
          if old.reinterpret_as_int() < src.reinterpret_as_int() {
            old
          } else {
            src
          } // AMOMIN.W
        0x14 =>
          if old.reinterpret_as_int() > src.reinterpret_as_int() {
            old
          } else {
            src
          } // AMOMAX.W
        0x18 => if old < src { old } else { src } // AMOMINU.W
        0x1C => if old > src { old } else { src } // AMOMAXU.W
        _ => raise illegal(inst)
      }
      self.ram.write32(off, nv)
      self.rset(rd, old)
    }
  }
}

///|
/// SYSTEM: ECALL/EBREAK/MRET/WFI and Zicsr.
fn Machine::exec_system(self : Machine, inst : UInt, rd : Int, rs1 : Int, funct3 : Int) -> Unit raise Trap {
  let next = self.pc + 4
  if funct3 == 0 {
    match inst {
      // ECALL (M-mode only hart)
      0x00000073 => raise Trap(cause=CAUSE_MACHINE_ECALL, tval=0)
      // EBREAK
      0x00100073 => raise Trap(cause=CAUSE_BREAKPOINT, tval=self.pc)
      // MRET
      0x30200073 => {
        let c = self.csr
        let mpie = (c.mstatus & MSTATUS_MPIE) != 0
        c.mstatus = (c.mstatus & (MSTATUS_MIE | MSTATUS_MPIE).lnot()) |
          (if mpie { MSTATUS_MIE } else { 0 }) |
          MSTATUS_MPIE |
          MSTATUS_MPP
        self.pc = c.mepc
      }
      // WFI: allowed to complete as a no-op
      0x10500073 => self.pc = next
      _ => raise illegal(inst)
    }
    return
  }
  // Zicsr
  let csr_addr = ((inst >> 20) & 0xFFF).reinterpret_as_int()
  let mtime = self.clint.mtime
  match funct3 {
    // CSRRW
    1 => {
      let old = if rd != 0 { self.csr.read(csr_addr, mtime) } else { 0 }
      self.csr.write(csr_addr, self.rget(rs1))
      self.rset(rd, old)
    }
    // CSRRS
    2 => {
      let old = self.csr.read(csr_addr, mtime)
      if rs1 != 0 {
        self.csr.write(csr_addr, old | self.rget(rs1))
      }
      self.rset(rd, old)
    }
    // CSRRC
    3 => {
      let old = self.csr.read(csr_addr, mtime)
      if rs1 != 0 {
        self.csr.write(csr_addr, old & self.rget(rs1).lnot())
      }
      self.rset(rd, old)
    }
    // CSRRWI
    5 => {
      let old = if rd != 0 { self.csr.read(csr_addr, mtime) } else { 0 }
      self.csr.write(csr_addr, rs1.reinterpret_as_uint())
      self.rset(rd, old)
    }
    // CSRRSI
    6 => {
      let old = self.csr.read(csr_addr, mtime)
      if rs1 != 0 {
        self.csr.write(csr_addr, old | rs1.reinterpret_as_uint())
      }
      self.rset(rd, old)
    }
    // CSRRCI
    7 => {
      let old = self.csr.read(csr_addr, mtime)
      if rs1 != 0 {
        self.csr.write(csr_addr, old & rs1.reinterpret_as_uint().lnot())
      }
      self.rset(rd, old)
    }
    _ => raise illegal(inst)
  }
  self.pc = next
}
