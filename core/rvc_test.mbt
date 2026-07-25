///|
/// Encodings cross-checked against clang/llvm-mc (llvm 18).
fn rvc_halves_to_bytes(halves : Array[UInt]) -> Bytes {
  let a : Array[Byte] = []
  for h in halves {
    a.push((h & 0xFF).to_byte())
    a.push(((h >> 8) & 0xFF).to_byte())
  }
  Bytes::from_array(a)
}

///|
test "rvc: arithmetic, jal link, branch and shifts" {
  let m = @core.Machine::new(ram_size=4096)
  m.load_image(
    @core.DRAM_BASE,
    rvc_halves_to_bytes([
      0x4529, // 0x00 c.li    a0, 10
      0x0505, // 0x02 c.addi  a0, 1      ; a0 = 11
      0x85AA, // 0x04 c.mv    a1, a0
      0x2011, // 0x06 c.jal   +4         ; ra = 0x08, -> 0x0a
      0x0001, // 0x08 c.nop              ; skipped
      0x0592, // 0x0a c.slli  a1, 4      ; a1 = 176
      0xC901, // 0x0c c.beqz  a0, +16    ; not taken
      0x8109, // 0x0e c.srli  a0, 2      ; a0 = 2
      0x890D, // 0x10 c.andi  a0, 3      ; a0 = 2
      0x8D89, // 0x12 c.sub   a1, a0     ; a1 = 174
      0xA001, // 0x14 c.j     0          ; idle loop
    ]),
  )
  let _ = m.run(10)
  inspect(m.reg(10), content="2") // a0
  inspect(m.reg(11), content="174") // a1
  inspect(m.reg(1), content="2147483656") // ra = 0x80000008 (pc+2)
  inspect(m.pc(), content="2147483668") // 0x80000014
}

///|
test "rvc: reserved encodings are illegal" {
  let m = @core.Machine::new(ram_size=4096)
  // c.addi4spn with nzuimm=0 (0x0000) is defined illegal
  m.load_image(@core.DRAM_BASE, rvc_halves_to_bytes([0x0000]))
  let _ = m.run(1)
  inspect(m.csr_peek(0x342).unwrap_or(999), content="2") // mcause = illegal
}
