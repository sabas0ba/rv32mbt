///|
fn words_to_bytes(words : Array[UInt]) -> Bytes {
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
test "trace emits spike-style commit log lines" {
  let m = @core.Machine::new(ram_size=4096)
  let lines : Array[String] = []
  m.set_trace(true)
  m.set_trace_sink(l => lines.push(l))
  m.load_image(
    @core.DRAM_BASE,
    words_to_bytes([
      0x100001B7, // lui  x3, 0x10000
      0x04100213, // addi x4, x0, 65
      0x00418023, // sb   x4, 0(x3)   ; no register writeback
    ]),
  )
  let _ = m.run(3)
  inspect(lines.length(), content="3")
  inspect(lines[0], content="core   0: 3 0x80000000 (0x100001b7) x3 0x10000000")
  inspect(lines[1], content="core   0: 3 0x80000004 (0x04100213) x4 0x00000041")
  inspect(lines[2], content="core   0: 3 0x80000008 (0x00418023)")
}

///|
test "trace can be disabled again" {
  let m = @core.Machine::new(ram_size=4096)
  let lines : Array[String] = []
  m.set_trace(true)
  m.set_trace_sink(l => lines.push(l))
  m.load_image(@core.DRAM_BASE, words_to_bytes([0x100001B7, 0x04100213]))
  let _ = m.run(1)
  m.set_trace(false)
  let _ = m.run(1)
  inspect(lines.length(), content="1")
}

///|
test "csr_peek reads CSRs without trapping" {
  let m = @core.Machine::new(ram_size=4096)
  inspect(m.csr_peek(0x300).unwrap_or(999), content="6144") // mstatus: MPP=3
  inspect(m.csr_peek(0x301).unwrap_or(999), content="1073746181") // misa: RV32IMAC
  inspect(m.csr_peek(0x342).unwrap_or(999), content="0") // mcause
  inspect(m.csr_peek(0x7C0) == None, content="true") // unimplemented
}

///|
test "peek8 reads DRAM only and has no device side effects" {
  let m = @core.Machine::new(ram_size=4096)
  m.load_image(@core.DRAM_BASE, words_to_bytes([0x100001B7]))
  inspect(m.peek8(@core.DRAM_BASE), content="183") // 0xB7
  inspect(m.peek8(@core.DRAM_BASE + 3), content="16") // 0x10
  inspect(m.peek8(@core.UART0_BASE), content="-1")
  inspect(m.peek8(0x00000000), content="-1")
}
