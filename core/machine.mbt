///|
/// Physical memory map, matching the QEMU virt machine
/// (QEMU v8.2.2 hw/riscv/virt.c, virt_memmap[]).
pub const DRAM_BASE : UInt = 0x80000000

///|
pub const UART0_BASE : UInt = 0x10000000

///|
pub const UART0_SIZE : UInt = 0x100

///|
pub const TEST_BASE : UInt = 0x00100000

///|
pub const TEST_SIZE : UInt = 0x1000

///|
pub const CLINT_BASE : UInt = 0x02000000

///|
pub const CLINT_SIZE : UInt = 0x10000

///|
pub const PLIC_BASE : UInt = 0x0C000000

///|
pub const PLIC_SIZE : UInt = 0x600000

///|
/// UART0 interrupt source number at the PLIC (QEMU virt: UART0_IRQ = 10).
pub const UART0_IRQ : Int = 10

///|
/// Single-hart RV32IMA machine (M-mode kernel + U-mode userspace; no
/// S-mode, no MMU, no PMP — U-mode may access all memory).
pub struct Machine {
  regs : FixedArray[UInt]
  mut pc : UInt
  /// Current privilege level: 3 = M, 0 = U.
  mut priv_level : Int
  csr : Csr
  ram : Ram
  uart : Uart
  clint : Clint
  plic : Plic
  /// LR/SC reservation: RAM offset of the reserved word, -1 = none.
  mut reservation : Int
  mut halted : Bool
  mut exit_code : Int
  /// riscv-tests HTIF: physical address of `tohost`, 0 = disabled.
  mut tohost : UInt
  /// Instruction tracing (spike-style commit log); see trace.mbt.
  mut trace : Bool
  mut trace_sink : ((String) -> Unit)?
  /// Register-file snapshot buffer used by step_traced.
  trace_regs : FixedArray[UInt]
}

///|
pub fn Machine::new(ram_size~ : Int = 128 * 1024 * 1024) -> Machine {
  {
    regs: FixedArray::make(32, 0),
    pc: DRAM_BASE,
    priv_level: 3,
    csr: Csr::new(),
    ram: Ram::new(ram_size),
    uart: Uart::new(),
    clint: Clint::new(),
    plic: Plic::new(),
    reservation: -1,
    halted: false,
    exit_code: 0,
    tohost: 0,
    trace: false,
    trace_sink: None,
    trace_regs: FixedArray::make(32, 0),
  }
}

///|
pub fn Machine::set_pc(self : Machine, pc : UInt) -> Unit {
  self.pc = pc
}

///|
pub fn Machine::pc(self : Machine) -> UInt {
  self.pc
}

///|
pub fn Machine::halted(self : Machine) -> Bool {
  self.halted
}

///|
/// Current privilege level (3 = M, 0 = U), for frontends and tests.
pub fn Machine::privilege(self : Machine) -> Int {
  self.priv_level
}

///|
pub fn Machine::exit_code(self : Machine) -> Int {
  self.exit_code
}

///|
pub fn Machine::set_tohost(self : Machine, addr : UInt) -> Unit {
  self.tohost = addr
}

///|
/// Register read; x0 is hardwired to zero.
fn Machine::rget(self : Machine, i : Int) -> UInt {
  self.regs.unsafe_get(i)
}

///|
fn Machine::rset(self : Machine, i : Int, v : UInt) -> Unit {
  if i != 0 {
    self.regs[i] = v
  }
}

///|
/// Read a general-purpose register (for frontends and tests).
pub fn Machine::reg(self : Machine, i : Int) -> UInt {
  self.regs[i]
}

///|
pub fn Machine::set_reg(self : Machine, i : Int, v : UInt) -> Unit {
  self.rset(i, v)
}

///|
/// Load a program image into physical memory.
pub fn Machine::load_image(self : Machine, addr : UInt, data : Bytes) -> Unit {
  self.ram.load_bytes((addr - DRAM_BASE).reinterpret_as_int(), data)
}

///|
pub fn Machine::uart(self : Machine) -> Uart {
  self.uart
}

///|
fn Machine::ram_off(self : Machine, addr : UInt, len : Int) -> Int? {
  if addr >= DRAM_BASE {
    let off = (addr - DRAM_BASE).reinterpret_as_int()
    if off >= 0 && off + len <= self.ram.size {
      return Some(off)
    }
  }
  None
}

///|
pub fn Machine::load8(self : Machine, addr : UInt) -> UInt raise Trap {
  match self.ram_off(addr, 1) {
    Some(off) => self.ram.read8(off)
    None =>
      if addr >= UART0_BASE && addr < UART0_BASE + UART0_SIZE {
        self.uart.read((addr - UART0_BASE).reinterpret_as_int())
      } else {
        raise Trap(cause=CAUSE_LOAD_ACCESS, tval=addr)
      }
  }
}

///|
pub fn Machine::load16(self : Machine, addr : UInt) -> UInt raise Trap {
  match self.ram_off(addr, 2) {
    Some(off) => self.ram.read16(off)
    None => raise Trap(cause=CAUSE_LOAD_ACCESS, tval=addr)
  }
}

///|
pub fn Machine::load32(self : Machine, addr : UInt) -> UInt raise Trap {
  match self.ram_off(addr, 4) {
    Some(off) => self.ram.read32(off)
    None =>
      if addr >= CLINT_BASE && addr < CLINT_BASE + CLINT_SIZE {
        self.clint.read32((addr - CLINT_BASE).reinterpret_as_int())
      } else if addr >= PLIC_BASE && addr < PLIC_BASE + PLIC_SIZE {
        self.plic.read32((addr - PLIC_BASE).reinterpret_as_int())
      } else if addr >= UART0_BASE && addr < UART0_BASE + UART0_SIZE {
        self.uart.read((addr - UART0_BASE).reinterpret_as_int())
      } else if addr >= TEST_BASE && addr < TEST_BASE + TEST_SIZE {
        // sifive_test reads as 0 (QEMU behavior); Linux syscon-reboot
        // reads the register before writing the magic value
        0
      } else {
        raise Trap(cause=CAUSE_LOAD_ACCESS, tval=addr)
      }
  }
}

///|
pub fn Machine::store8(self : Machine, addr : UInt, v : UInt) -> Unit raise Trap {
  match self.ram_off(addr, 1) {
    Some(off) => self.ram.write8(off, v)
    None =>
      if addr >= UART0_BASE && addr < UART0_BASE + UART0_SIZE {
        self.uart.write((addr - UART0_BASE).reinterpret_as_int(), v)
      } else {
        raise Trap(cause=CAUSE_STORE_ACCESS, tval=addr)
      }
  }
}

///|
pub fn Machine::store16(self : Machine, addr : UInt, v : UInt) -> Unit raise Trap {
  match self.ram_off(addr, 2) {
    Some(off) => self.ram.write16(off, v)
    None => raise Trap(cause=CAUSE_STORE_ACCESS, tval=addr)
  }
}

///|
pub fn Machine::store32(self : Machine, addr : UInt, v : UInt) -> Unit raise Trap {
  if self.tohost != 0 && addr == self.tohost {
    // riscv-tests HTIF exit: 1 = pass, (n << 1) | 1 = fail n
    self.halted = true
    self.exit_code = if v == 1 {
      0
    } else {
      (v >> 1).reinterpret_as_int()
    }
    return
  }
  match self.ram_off(addr, 4) {
    Some(off) => self.ram.write32(off, v)
    None =>
      if addr >= CLINT_BASE && addr < CLINT_BASE + CLINT_SIZE {
        self.clint.write32((addr - CLINT_BASE).reinterpret_as_int(), v)
      } else if addr >= PLIC_BASE && addr < PLIC_BASE + PLIC_SIZE {
        self.plic.write32((addr - PLIC_BASE).reinterpret_as_int(), v)
      } else if addr >= TEST_BASE && addr < TEST_BASE + TEST_SIZE {
        // sifive_test finisher: 0x5555 pass, 0x3333 fail, 0x7777 reset
        let kind = v & 0xFFFF
        if kind == 0x5555 {
          self.halted = true
          self.exit_code = 0
        } else if kind == 0x3333 {
          self.halted = true
          self.exit_code = (v >> 16).reinterpret_as_int()
        } else if kind == 0x7777 {
          // reset is not supported; halt instead
          self.halted = true
          self.exit_code = 0
        }
      } else if addr >= UART0_BASE && addr < UART0_BASE + UART0_SIZE {
        self.uart.write((addr - UART0_BASE).reinterpret_as_int(), v)
      } else {
        raise Trap(cause=CAUSE_STORE_ACCESS, tval=addr)
      }
  }
}

///|
/// Enter the trap handler (mtvec).
fn Machine::take_trap(self : Machine, cause : Int, tval : UInt, interrupt~ : Bool = false) -> Unit {
  let c = self.csr
  c.mepc = self.pc
  c.mcause = cause.reinterpret_as_uint() |
    (if interrupt { 0x80000000U } else { 0 })
  c.mtval = tval
  // MPIE <- MIE, MIE <- 0, MPP <- current privilege
  let mie_set = (c.mstatus & MSTATUS_MIE) != 0
  let mpp = (self.priv_level.reinterpret_as_uint() << 11) & MSTATUS_MPP
  c.mstatus = (c.mstatus & (MSTATUS_MIE | MSTATUS_MPIE | MSTATUS_MPP).lnot()) |
    (if mie_set { MSTATUS_MPIE } else { 0 }) |
    mpp
  self.priv_level = 3
  let base = self.csr.mtvec & 0xFFFFFFFC
  self.pc = if interrupt && (self.csr.mtvec & 0x3) == 1 {
    base + (cause.reinterpret_as_uint() << 2)
  } else {
    base
  }
}

///|
/// Refresh mip from device state and take one pending enabled interrupt,
/// if any. Priority: external > software > timer.
fn Machine::check_interrupt(self : Machine) -> Bool {
  let uart_level : UInt = if self.uart.irq_pending() {
    1U << UART0_IRQ
  } else {
    0
  }
  self.plic.update(uart_level)
  let c = self.csr
  c.mip = (if self.plic.eip() { 1U << IRQ_M_EXT } else { 0 }) |
    (if self.clint.msip { 1U << IRQ_M_SOFT } else { 0 }) |
    (if self.clint.timer_pending() { 1U << IRQ_M_TIMER } else { 0 })
  // M-level interrupts are globally enabled while running at a lower
  // privilege level, regardless of mstatus.MIE
  if self.priv_level == 3 && (c.mstatus & MSTATUS_MIE) == 0 {
    return false
  }
  let pending = c.mip & c.mie
  if pending == 0 {
    return false
  }
  let cause = if ((pending >> IRQ_M_EXT) & 1) != 0 {
    IRQ_M_EXT
  } else if ((pending >> IRQ_M_SOFT) & 1) != 0 {
    IRQ_M_SOFT
  } else {
    IRQ_M_TIMER
  }
  self.take_trap(cause, 0, interrupt=true)
  true
}

///|
/// Execute one instruction (or take one interrupt).
pub fn Machine::step(self : Machine) -> Unit {
  if self.halted {
    return
  }
  self.clint.tick(1)
  self.csr.mcycle = self.csr.mcycle + 1
  if self.check_interrupt() {
    return
  }
  if self.trace {
    self.step_traced()
  } else {
    self.step_no_interrupt() catch {
      Trap(cause~, tval~) => self.take_trap(cause, tval)
    }
  }
}

///|
fn Machine::step_no_interrupt(self : Machine) -> Unit raise Trap {
  if (self.pc & 0x3) != 0 {
    raise Trap(cause=CAUSE_MISALIGNED_FETCH, tval=self.pc)
  }
  let inst = match self.ram_off(self.pc, 4) {
    Some(off) => self.ram.read32(off)
    None => raise Trap(cause=CAUSE_FETCH_ACCESS, tval=self.pc)
  }
  self.execute(inst)
  self.csr.minstret = self.csr.minstret + 1
}

///|
/// WFI idle-time skip: when the timer interrupt is the wake source and
/// is armed, jump mtime forward to mtimecmp so the interrupt fires on
/// the next step instead of busy-spinning through the idle period
/// (tickless emulation). Other wake sources (UART RX via PLIC, msip)
/// are unaffected because WFI still retires and interrupts are checked
/// every step.
fn Machine::wfi_hint(self : Machine) -> Unit {
  let cmp = self.clint.mtimecmp
  if ((self.csr.mie >> IRQ_M_TIMER) & 1) != 0 &&
    cmp != 0xFFFFFFFFFFFFFFFFUL &&
    cmp > self.clint.mtime {
    self.clint.mtime = cmp
  }
}

///|
/// Run up to `max_steps` instructions. Returns the number executed.
pub fn Machine::run(self : Machine, max_steps : Int) -> Int {
  for i in 0..<max_steps {
    if self.halted {
      break i
    }
    self.step()
  } nobreak {
    max_steps
  }
}
