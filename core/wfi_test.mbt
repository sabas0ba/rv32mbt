///|
fn wfi_words_to_bytes(words : Array[UInt]) -> Bytes {
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
test "wfi fast-forwards mtime to an armed mtimecmp" {
  let m = @core.Machine::new(ram_size=4096)
  m.load_image(
    @core.DRAM_BASE,
    wfi_words_to_bytes([
      0x020042B7, // lui   x5, 0x2004     ; CLINT mtimecmp
      0x3E800313, // addi  x6, x0, 1000
      0x0062A023, // sw    x6, 0(x5)      ; mtimecmp lo = 1000
      0x0002A223, // sw    x0, 4(x5)      ; mtimecmp hi = 0
      0x08000393, // addi  x7, x0, 0x80   ; MTIE
      0x30439073, // csrw  mie, x7
      0x10500073, // wfi
    ]),
  )
  let _ = m.run(7)
  // idle time was skipped: mtime jumped to mtimecmp
  inspect(m.csr_peek(0xC01).unwrap_or(0), content="1000")
}

///|
test "sifive_test region reads as zero (syscon regmap does reads)" {
  let m = @core.Machine::new(ram_size=4096)
  m.load_image(
    @core.DRAM_BASE,
    wfi_words_to_bytes([
      0x001002B7, // lui x5, 0x100      ; TEST_BASE
      0x0002A303, // lw  x6, 0(x5)
    ]),
  )
  let _ = m.run(2)
  inspect(m.reg(6).reinterpret_as_int(), content="0")
  inspect(m.halted(), content="false")
}

///|
test "wfi is a no-op when no timer is armed" {
  let m = @core.Machine::new(ram_size=4096)
  m.load_image(@core.DRAM_BASE, wfi_words_to_bytes([0x10500073]))
  let _ = m.run(1)
  inspect(m.csr_peek(0xC01).unwrap_or(999), content="1") // one tick only
}
