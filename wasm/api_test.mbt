///|
/// Drive the Int-only export surface end to end on the wasm-gc backend:
/// stage a flat binary that prints 'A' to UART0 and exits through the
/// sifive_test finisher, then drain the output byte by byte.

///|
fn stage_word(w : UInt) -> Unit {
  @wasm.vm_stage_push((w & 0xFF).reinterpret_as_int())
  @wasm.vm_stage_push(((w >> 8) & 0xFF).reinterpret_as_int())
  @wasm.vm_stage_push(((w >> 16) & 0xFF).reinterpret_as_int())
  @wasm.vm_stage_push(((w >> 24) & 0xFF).reinterpret_as_int())
}

///|
test "stage/load/run/drain via Int-only api" {
  @wasm.vm_create(1)
  let program : Array[UInt] = [
    0x100001B7, // lui  x3, 0x10000      ; UART0 base
    0x04100213, // addi x4, x0, 65       ; 'A'
    0x00418023, // sb   x4, 0(x3)
    0x00005537, // lui  x10, 0x5
    0x55550513, // addi x10, x10, 0x555  ; a0 = 0x5555 (FINISHER_PASS)
    0x001005B7, // lui  x11, 0x100       ; sifive_test base
    0x00A5A023, // sw   x10, 0(x11)
  ]
  for w in program {
    stage_word(w)
  }
  @wasm.vm_load_bin_staged()
  inspect(@wasm.vm_pc(), content="-2147483648") // 0x80000000
  let executed = @wasm.vm_run(100)
  inspect(executed, content="7")
  inspect(@wasm.vm_halted(), content="1")
  inspect(@wasm.vm_exit_code(), content="0")
  inspect(@wasm.vm_take_byte(), content="65")
  inspect(@wasm.vm_take_byte(), content="-1")
}

///|
test "step, registers, peek and trace via Int-only api" {
  @wasm.vm_create(1)
  @wasm.vm_set_trace(1)
  let program : Array[UInt] = [
    0x100001B7, // lui  x3, 0x10000
    0x04100213, // addi x4, x0, 65
  ]
  for w in program {
    stage_word(w)
  }
  @wasm.vm_load_bin_staged()
  inspect(@wasm.vm_peek(-2147483648), content="183") // 0x80000000 -> 0xB7
  inspect(@wasm.vm_peek(0x10000000), content="-1") // MMIO is not peekable
  inspect(@wasm.vm_step(), content="1")
  inspect(@wasm.vm_reg(3), content="268435456") // x3 = 0x10000000
  inspect(@wasm.vm_step(), content="1")
  inspect(@wasm.vm_reg(4), content="65")
  // drain the two trace lines and check the first one byte-wise
  let sb = StringBuilder::new()
  let mut b = @wasm.vm_trace_take_byte()
  while b >= 0 {
    sb.write_char(b.unsafe_to_char())
    b = @wasm.vm_trace_take_byte()
  }
  inspect(
    sb.to_string(),
    content="core   0: 3 0x80000000 (0x100001b7) x3 0x10000000\ncore   0: 3 0x80000004 (0x04100213) x4 0x00000041\n",
  )
}

///|
test "elf load rejects garbage" {
  @wasm.vm_create(1)
  @wasm.vm_stage_push(0x7F)
  @wasm.vm_stage_push(0x45)
  inspect(@wasm.vm_load_elf_staged(), content="-1")
}
