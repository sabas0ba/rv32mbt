///|
/// RVC (compressed) instruction expansion for RV32C. Each 16-bit
/// instruction is expanded to its 32-bit equivalent and executed by
/// the normal decoder; the instruction length is threaded through
/// `execute` so link registers and fall-through addresses use pc+2.
/// FP loads/stores (C.FLD/C.FLW/...) are illegal: no F/D extension.

///|
fn r_enc(f7 : UInt, rs2 : Int, rs1 : Int, f3 : UInt, rd : Int, op : UInt) -> UInt {
  (f7 << 25) |
  (rs2.reinterpret_as_uint() << 20) |
  (rs1.reinterpret_as_uint() << 15) |
  (f3 << 12) |
  (rd.reinterpret_as_uint() << 7) |
  op
}

///|
fn i_enc(imm : UInt, rs1 : Int, f3 : UInt, rd : Int, op : UInt) -> UInt {
  ((imm & 0xFFF) << 20) |
  (rs1.reinterpret_as_uint() << 15) |
  (f3 << 12) |
  (rd.reinterpret_as_uint() << 7) |
  op
}

///|
fn s_enc(imm : UInt, rs2 : Int, rs1 : Int, f3 : UInt) -> UInt {
  (((imm >> 5) & 0x7F) << 25) |
  (rs2.reinterpret_as_uint() << 20) |
  (rs1.reinterpret_as_uint() << 15) |
  (f3 << 12) |
  ((imm & 0x1F) << 7) |
  0x23
}

///|
fn b_enc(imm : UInt, rs2 : Int, rs1 : Int, f3 : UInt) -> UInt {
  (((imm >> 12) & 0x1) << 31) |
  (((imm >> 5) & 0x3F) << 25) |
  (rs2.reinterpret_as_uint() << 20) |
  (rs1.reinterpret_as_uint() << 15) |
  (f3 << 12) |
  (((imm >> 1) & 0xF) << 8) |
  (((imm >> 11) & 0x1) << 7) |
  0x63
}

///|
fn j_enc(imm : UInt, rd : Int) -> UInt {
  (((imm >> 20) & 0x1) << 31) |
  (((imm >> 1) & 0x3FF) << 21) |
  (((imm >> 11) & 0x1) << 20) |
  (((imm >> 12) & 0xFF) << 12) |
  (rd.reinterpret_as_uint() << 7) |
  0x6F
}

///|
/// C.J / C.JAL offset: [11|4|9:8|10|6|7|3:1|5] from c[12:2].
fn cj_imm(c : UInt) -> UInt {
  sext(
    ((c >> 1) & 0x800) |
    ((c >> 7) & 0x10) |
    ((c >> 1) & 0x300) |
    ((c << 2) & 0x400) |
    ((c >> 1) & 0x40) |
    ((c << 1) & 0x80) |
    ((c >> 2) & 0xE) |
    ((c << 3) & 0x20),
    12,
  )
}

///|
/// C.BEQZ / C.BNEZ offset: [8|4:3|7:6|2:1|5] from c[12:10], c[6:2].
fn cb_imm(c : UInt) -> UInt {
  sext(
    ((c >> 4) & 0x100) |
    ((c >> 7) & 0x18) |
    ((c << 1) & 0xC0) |
    ((c >> 2) & 0x6) |
    ((c << 3) & 0x20),
    9,
  )
}

///|
/// 6-bit signed immediate [12|6:2] (C.ADDI, C.LI, C.ANDI).
fn ci_imm(c : UInt) -> UInt {
  sext(((c >> 7) & 0x20) | ((c >> 2) & 0x1F), 6)
}

///|
/// Shift amount [12|6:2]; bit 5 set is reserved on RV32.
fn ci_shamt(c : UInt) -> UInt raise Trap {
  let sh = ((c >> 7) & 0x20) | ((c >> 2) & 0x1F)
  if (sh & 0x20) != 0 {
    raise illegal(c)
  }
  sh
}

///|
/// Expand one 16-bit instruction; raises an illegal-instruction trap
/// for reserved and FP encodings.
fn expand_rvc(c : UInt) -> UInt raise Trap {
  let op = c & 0x3
  let f3 = (c >> 13) & 0x7
  // the compressed register fields address x8..x15
  let rdp = (((c >> 2) & 0x7) + 8).reinterpret_as_int()
  let rs1p = (((c >> 7) & 0x7) + 8).reinterpret_as_int()
  let rfull = ((c >> 7) & 0x1F).reinterpret_as_int()
  match op {
    0 =>
      match f3 {
        // C.ADDI4SPN: addi rd', x2, nzuimm[9:2]
        0 => {
          let imm = ((c >> 7) & 0x30) |
            ((c >> 1) & 0x3C0) |
            ((c >> 4) & 0x4) |
            ((c >> 2) & 0x8)
          if imm == 0 {
            raise illegal(c)
          }
          i_enc(imm, 2, 0, rdp, 0x13)
        }
        // C.LW: lw rd', uimm[6:2](rs1')
        2 => {
          let imm = ((c >> 7) & 0x38) | ((c >> 4) & 0x4) | ((c << 1) & 0x40)
          i_enc(imm, rs1p, 2, rdp, 0x03)
        }
        // C.SW: sw rs2', uimm[6:2](rs1')
        6 => {
          let imm = ((c >> 7) & 0x38) | ((c >> 4) & 0x4) | ((c << 1) & 0x40)
          s_enc(imm, rdp, rs1p, 2)
        }
        _ => raise illegal(c)
      }
    1 =>
      match f3 {
        // C.NOP / C.ADDI
        0 => i_enc(ci_imm(c), rfull, 0, rfull, 0x13)
        // C.JAL (RV32)
        1 => j_enc(cj_imm(c), 1)
        // C.LI: addi rd, x0, imm
        2 => i_enc(ci_imm(c), 0, 0, rfull, 0x13)
        3 =>
          if rfull == 2 {
            // C.ADDI16SP: addi x2, x2, nzimm[9:4]
            let imm = sext(
              ((c >> 3) & 0x200) |
              ((c >> 2) & 0x10) |
              ((c << 1) & 0x40) |
              ((c << 4) & 0x180) |
              ((c << 3) & 0x20),
              10,
            )
            if imm == 0 {
              raise illegal(c)
            }
            i_enc(imm, 2, 0, 2, 0x13)
          } else {
            // C.LUI: lui rd, nzimm[17:12]
            let imm = sext((((c >> 12) & 0x1) << 17) | (((c >> 2) & 0x1F) << 12), 18)
            if imm == 0 {
              raise illegal(c)
            }
            (imm & 0xFFFFF000) | (rfull.reinterpret_as_uint() << 7) | 0x37
          }
        4 => {
          let f2 = (c >> 10) & 0x3
          match f2 {
            // C.SRLI / C.SRAI / C.ANDI (rd = rs1')
            0 => i_enc(ci_shamt(c), rs1p, 5, rs1p, 0x13)
            1 => i_enc(ci_shamt(c) | 0x400, rs1p, 5, rs1p, 0x13)
            2 => i_enc(ci_imm(c), rs1p, 7, rs1p, 0x13)
            _ => {
              if ((c >> 12) & 0x1) != 0 {
                // C.SUBW/C.ADDW are RV64
                raise illegal(c)
              }
              match (c >> 5) & 0x3 {
                0 => r_enc(0x20, rdp, rs1p, 0, rs1p, 0x33) // C.SUB
                1 => r_enc(0x00, rdp, rs1p, 4, rs1p, 0x33) // C.XOR
                2 => r_enc(0x00, rdp, rs1p, 6, rs1p, 0x33) // C.OR
                _ => r_enc(0x00, rdp, rs1p, 7, rs1p, 0x33) // C.AND
              }
            }
          }
        }
        // C.J
        5 => j_enc(cj_imm(c), 0)
        // C.BEQZ / C.BNEZ: beq/bne rs1', x0, offset
        6 => b_enc(cb_imm(c), 0, rs1p, 0)
        _ => b_enc(cb_imm(c), 0, rs1p, 1)
      }
    2 =>
      match f3 {
        // C.SLLI
        0 => i_enc(ci_shamt(c), rfull, 1, rfull, 0x13)
        // C.LWSP: lw rd, uimm[7:2](x2)
        2 => {
          if rfull == 0 {
            raise illegal(c)
          }
          let imm = ((c >> 7) & 0x20) | ((c >> 2) & 0x1C) | ((c << 4) & 0xC0)
          i_enc(imm, 2, 2, rfull, 0x03)
        }
        4 => {
          let rs2 = ((c >> 2) & 0x1F).reinterpret_as_int()
          if ((c >> 12) & 0x1) == 0 {
            if rs2 == 0 {
              // C.JR: jalr x0, rs1, 0
              if rfull == 0 {
                raise illegal(c)
              }
              i_enc(0, rfull, 0, 0, 0x67)
            } else {
              // C.MV: add rd, x0, rs2
              r_enc(0x00, rs2, 0, 0, rfull, 0x33)
            }
          } else if rs2 == 0 {
            if rfull == 0 {
              // C.EBREAK
              0x00100073
            } else {
              // C.JALR: jalr x1, rs1, 0
              i_enc(0, rfull, 0, 1, 0x67)
            }
          } else {
            // C.ADD: add rd, rd, rs2
            r_enc(0x00, rs2, rfull, 0, rfull, 0x33)
          }
        }
        // C.SWSP: sw rs2, uimm[7:2](x2)
        6 => {
          let imm = ((c >> 7) & 0x3C) | ((c >> 1) & 0xC0)
          s_enc(imm, ((c >> 2) & 0x1F).reinterpret_as_int(), 2, 2)
        }
        _ => raise illegal(c)
      }
    _ => raise illegal(c)
  }
}
