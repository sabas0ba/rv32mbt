///|
fn priv_words_to_bytes(words : Array[UInt]) -> Bytes {
  let a : Array[Byte] = []
  for w in words {
    a.push((w & 0xFF).to_byte())
    a.push(((w >> 8) & 0xFF).to_byte())
    a.push(((w >> 16) & 0xFF).to_byte())
    a.push(((w >> 24) & 0xFF).to_byte())
  }
  Bytes::from_array(a)
}

///|
/// mret with MPP=U drops to U-mode; ecall from U traps with cause 8
/// and returns the hart to M-mode.
test "mret to U-mode and user ecall" {
  let m = @core.Machine::new(ram_size=4096)
  m.load_image(
    @core.DRAM_BASE,
    priv_words_to_bytes([
      0x00000297, // 0x00 auipc x5, 0        ; x5 = 0x80000000
      0x03028293, // 0x04 addi  x5, x5, 0x30 ; trap handler
      0x30529073, // 0x08 csrw  mtvec, x5
      0x01028313, // 0x0c addi  x6, x5, 0x10 ; user entry 0x80000040
      0x34131073, // 0x10 csrw  mepc, x6
      0x30001073, // 0x14 csrw  mstatus, x0  ; MPP <- U
      0x30200073, // 0x18 mret               ; enter U-mode
      0x00000000, // 0x1c
      0x00000000, // 0x20
      0x00000000, // 0x24
      0x00000000, // 0x28
      0x00000000, // 0x2c
      0x342023F3, // 0x30 csrr  x7, mcause   ; trap handler
      0x0000006F, // 0x34 j     .
      0x00000000, // 0x38
      0x00000000, // 0x3c
      0x00000073, // 0x40 ecall              ; user code
    ]),
  )
  let _ = m.run(6)
  inspect(m.privilege(), content="3")
  let _ = m.run(1) // mret
  inspect(m.privilege(), content="0")
  inspect(m.pc(), content="2147483712") // 0x80000040
  let _ = m.run(3) // ecall -> handler
  inspect(m.privilege(), content="3")
  inspect(m.reg(7), content="8") // CAUSE_USER_ECALL
  inspect(m.csr_peek(0x341).unwrap_or(0), content="2147483712") // mepc
}

///|
/// U-mode may read the user counters (0xC0x) but machine CSRs trap
/// with an illegal-instruction exception.
test "U-mode csr privilege check" {
  let m = @core.Machine::new(ram_size=4096)
  m.load_image(
    @core.DRAM_BASE,
    priv_words_to_bytes([
      0x00000297, // 0x00 auipc x5, 0
      0x03028293, // 0x04 addi  x5, x5, 0x30
      0x30529073, // 0x08 csrw  mtvec, x5
      0x01028313, // 0x0c addi  x6, x5, 0x10
      0x34131073, // 0x10 csrw  mepc, x6
      0x30001073, // 0x14 csrw  mstatus, x0
      0x30200073, // 0x18 mret
      0x00000000, // 0x1c
      0x00000000, // 0x20
      0x00000000, // 0x24
      0x00000000, // 0x28
      0x00000000, // 0x2c
      0x342023F3, // 0x30 csrr  x7, mcause
      0x0000006F, // 0x34 j     .
      0x00000000, // 0x38
      0x00000000, // 0x3c
      0xC01024F3, // 0x40 rdtime x9           ; allowed in U-mode
      0x300024F3, // 0x44 csrr  x8, mstatus   ; illegal in U-mode
    ]),
  )
  let _ = m.run(20)
  inspect(m.privilege(), content="3")
  inspect(m.reg(9) > 0, content="true") // rdtime succeeded
  inspect(m.reg(8), content="0") // mstatus read never retired
  inspect(m.reg(7), content="2") // CAUSE_ILLEGAL_INSTRUCTION
}

///|
/// A pending M-level interrupt is taken in U-mode even with
/// mstatus.MIE clear.
test "interrupts fire in U-mode regardless of MIE" {
  let m = @core.Machine::new(ram_size=4096)
  m.load_image(
    @core.DRAM_BASE,
    priv_words_to_bytes([
      0x020042B7, // 0x00 lui   x5, 0x2004   ; CLINT mtimecmp
      0x03200313, // 0x04 addi  x6, x0, 50
      0x0062A023, // 0x08 sw    x6, 0(x5)
      0x0002A223, // 0x0c sw    x0, 4(x5)
      0x08000393, // 0x10 addi  x7, x0, 0x80 ; MTIE
      0x30439073, // 0x14 csrw  mie, x7
      0x00000297, // 0x18 auipc x5, 0        ; x5 = 0x80000018
      0x02828293, // 0x1c addi  x5, x5, 0x28 ; handler 0x80000040
      0x30529073, // 0x20 csrw  mtvec, x5
      0x01028313, // 0x24 addi  x6, x5, 0x10 ; user entry 0x80000050
      0x34131073, // 0x28 csrw  mepc, x6
      0x30001073, // 0x2c csrw  mstatus, x0  ; MIE=0, MPP=U
      0x30200073, // 0x30 mret
      0x00000000, // 0x34
      0x00000000, // 0x38
      0x00000000, // 0x3c
      0x342023F3, // 0x40 csrr  x7, mcause
      0x0000006F, // 0x44 j     .
      0x00000000, // 0x48
      0x00000000, // 0x4c
      0x0000006F, // 0x50 j     .            ; user idle loop
    ]),
  )
  let _ = m.run(100)
  inspect(m.privilege(), content="3")
  inspect(m.reg(7), content="2147483655") // 0x80000007 = M timer interrupt
}
