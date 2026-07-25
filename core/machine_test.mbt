///|
/// Helper: build a machine with a small DRAM and a program at DRAM_BASE.
fn boot(prog : Array[UInt]) -> @core.Machine {
  let m = @core.Machine::new(ram_size=1024 * 1024)
  let mut addr = @core.DRAM_BASE
  for w in prog {
    try! m.store32(addr, w)
    addr = addr + 4
  }
  m.set_pc(@core.DRAM_BASE)
  m
}

///|
test "addi lui add sub" {
  let m = boot([
    0x02A00093, // addi x1, x0, 42
    0xDEADB137, // lui  x2, 0xDEADB
    0x001081B3, // add  x3, x1, x1
    0x402081B3, // sub  x3, x1, x2
  ])
  let _ = m.run(4)
  inspect(m.reg(1), content="42")
  inspect(m.reg(2), content="3735924736") // 0xDEADB000
  inspect(m.reg(3), content="559042602") // (42 - 0xDEADB000) mod 2^32
}

///|
test "mul mulh mulhu div rem including division by zero" {
  let m = boot([
    0xFFF00093, // addi  x1, x0, -1
    0x00200113, // addi  x2, x0, 2
    0x022081B3, // mul   x3, x1, x2  = -2
    0x02209233, // mulh  x4, x1, x2  = -1
    0x0220B2B3, // mulhu x5, x1, x2  = 1
    0x0220C333, // div   x6, x1, x2  = 0
    0x0200C3B3, // div   x7, x1, x0  = -1
    0x0200E433, // rem   x8, x1, x0  = x1
  ])
  let _ = m.run(8)
  inspect(m.reg(3), content="4294967294")
  inspect(m.reg(4), content="4294967295")
  inspect(m.reg(5), content="1")
  inspect(m.reg(6), content="0")
  inspect(m.reg(7), content="4294967295")
  inspect(m.reg(8), content="4294967295")
}

///|
test "load store roundtrip" {
  let m = boot([
    0x02A00093, // addi x1, x0, 42
    0x80000237, // lui  x4, 0x80000
    0x10122423, // sw   x1, 0x108(x4)
    0x10822183, // lw   x3, 0x108(x4)
    0x10824283, // lbu  x5, 0x108(x4)
  ])
  let _ = m.run(5)
  inspect(m.reg(3), content="42")
  inspect(m.reg(5), content="42")
}

///|
test "branch taken skips instruction" {
  let m = boot([
    0x02A00093, // addi x1, x0, 42
    0x02A00113, // addi x2, x0, 42
    0x00208463, // beq  x1, x2, +8
    0x06300193, // addi x3, x0, 99  (skipped)
    0x00100213, // addi x4, x0, 1
  ])
  let _ = m.run(4)
  inspect(m.reg(3), content="0")
  inspect(m.reg(4), content="1")
}

///|
test "ecall sets mcause and jumps to mtvec" {
  let m = boot([
    0x800002B7, // lui   x5, 0x80000
    0x02028293, // addi  x5, x5, 32   ; handler at DRAM_BASE+0x20
    0x30529073, // csrrw x0, mtvec, x5
    0x00000073, // ecall
    0x00000013, // nop
    0x00000013, // nop
    0x00000013, // nop
    0x00000013, // nop
    0x342022F3, // handler: csrrs x5, mcause, x0
  ])
  let _ = m.run(5)
  inspect(m.reg(5), content="11") // machine ecall
  inspect(m.pc(), content="2147483684") // 0x80000024
}

///|
test "uart transmit via sb" {
  let m = boot([
    0x02A00093, // addi x1, x0, 42
    0x10000337, // lui  x6, 0x10000
    0x00130023, // sb   x1, 0(x6)
  ])
  let sent : Array[Int] = []
  m.uart().set_tx(b => sent.push(b.to_int()))
  let _ = m.run(3)
  assert_eq(sent.length(), 1)
  inspect(sent[0], content="42")
}

///|
test "uart lsr and rbr reflect rx queue" {
  let m = @core.Machine::new(ram_size=4096)
  inspect(m.uart().read(5), content="96") // 0x60: THRE|TEMT
  m.uart().push_rx(b'a')
  inspect(m.uart().read(5), content="97") // 0x61: +DR
  inspect(m.uart().read(0), content="97") // 'a'
  inspect(m.uart().read(5), content="96")
}

///|
test "amoadd then lr sc" {
  let m = boot([
    0x02A00093, // addi x1, x0, 42
    0x80000237, // lui  x4, 0x80000
    0x10020213, // addi x4, x4, 0x100
    0x00122023, // sw   x1, 0(x4)
    0x001221AF, // amoadd.w x3, x1, (x4)   ; x3=42, mem=84
    0x00022283, // lw   x5, 0(x4)          ; x5=84
    0x1002232F, // lr.w x6, (x4)           ; x6=84, reserve
    0x181223AF, // sc.w x7, x1, (x4)       ; x7=0, mem=42
  ])
  let _ = m.run(8)
  inspect(m.reg(3), content="42")
  inspect(m.reg(5), content="84")
  inspect(m.reg(6), content="84")
  inspect(m.reg(7), content="0")
  let v = try! m.load32(@core.DRAM_BASE + 0x100)
  inspect(v, content="42")
}

///|
test "sifive test finisher pass halts machine" {
  let m = boot([
    0x00100137, // lui  x2, 0x100      ; TEST_BASE
    0x000050B7, // lui  x1, 0x5
    0x55508093, // addi x1, x1, 0x555  ; x1 = 0x5555
    0x00112023, // sw   x1, 0(x2)
  ])
  let _ = m.run(4)
  inspect(m.halted(), content="true")
  inspect(m.exit_code(), content="0")
}

///|
test "timer interrupt vectors to mtvec" {
  // mtvec = DRAM_BASE+0x40 (direct); enable MTIE and MIE; set mtimecmp=0
  // via CLINT store, then loop. The pending timer interrupt must redirect
  // control to the handler, which reads mcause.
  let m = boot([
    0x800002B7, // lui   x5, 0x80000
    0x04028293, // addi  x5, x5, 0x40
    0x30529073, // csrrw x0, mtvec, x5
    0x00000313, // addi  x6, x0, 0     ; mtimecmp value 0 (already passed)
    0x020002B7, // lui   x5, 0x2000    ; CLINT_BASE
    0x00400393, // addi  x7, x0, 4
    0x0062A023, // sw    x6, 0(x5)     ; placeholder (msip=0)
    0x08000093, // addi  x1, x0, 128   ; MIE.MTIE
    0x30409073, // csrrw x0, mie, x1
    0x00800093, // addi  x1, x0, 8     ; mstatus.MIE
    0x3000A073, // csrrs x0, mstatus, x1
    0x0000006F, // jal   x0, 0         ; spin
    0x00000013,
    0x00000013,
    0x00000013,
    0x00000013,
    0x342023F3, // handler at +0x40: csrrs x7, mcause, x0
    0x0000006F, // jal x0, 0 ; spin so the handler result is preserved
  ])
  // mtimecmp defaults to all-ones; write 0 via the bus to arm it
  try! m.store32(@core.CLINT_BASE + 0x4000, 0)
  try! m.store32(@core.CLINT_BASE + 0x4004, 0)
  let _ = m.run(20)
  inspect(m.reg(7), content="2147483655") // 0x80000007: interrupt | timer
}
