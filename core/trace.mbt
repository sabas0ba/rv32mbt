///|
/// Instruction tracing in the style of spike's commit log:
///
///   core   0: 3 0x80000000 (0x00100537) x10 0x00100000
///
/// "3" is the privilege level (this machine is M-mode only). The
/// register operand is recovered by comparing the register file before
/// and after execution, so a write that leaves the register value
/// unchanged is not shown; memory operands are not logged.

///|
fn hex8(v : UInt) -> String {
  let sb = StringBuilder::new()
  for i in 0..<8 {
    let nib = ((v >> ((7 - i) * 4)) & 0xF).reinterpret_as_int()
    sb.write_char((if nib < 10 { 48 + nib } else { 87 + nib }).unsafe_to_char())
  }
  sb.to_string()
}

///|
/// Enable or disable per-instruction tracing. Lines are delivered to
/// the sink installed with `set_trace_sink`.
pub fn Machine::set_trace(self : Machine, on : Bool) -> Unit {
  self.trace = on
}

///|
pub fn Machine::set_trace_sink(self : Machine, sink : (String) -> Unit) -> Unit {
  self.trace_sink = Some(sink)
}

///|
/// step_no_interrupt plus commit-log emission. Kept out of the fast
/// path; Machine::step dispatches here only when tracing is enabled.
fn Machine::step_traced(self : Machine) -> Unit {
  let pc0 = self.pc
  let priv0 = self.priv_level
  let inst = match self.ram_off(pc0, 4) {
    Some(off) => self.ram.read32(off)
    None => 0
  }
  for i in 0..<32 {
    self.trace_regs[i] = self.regs[i]
  }
  self.step_no_interrupt() catch {
    Trap(cause~, tval~) => self.take_trap(cause, tval)
  }
  match self.trace_sink {
    Some(sink) => {
      let sb = StringBuilder::new()
      sb.write_string("core   0: ")
      sb.write_string(priv0.to_string())
      sb.write_string(" 0x")
      sb.write_string(hex8(pc0))
      sb.write_string(" (0x")
      sb.write_string(hex8(inst))
      sb.write_string(")")
      for i in 1..<32 {
        if self.regs[i] != self.trace_regs[i] {
          sb.write_string(" x")
          sb.write_string(i.to_string())
          sb.write_string(" 0x")
          sb.write_string(hex8(self.regs[i]))
          break
        }
      }
      sink(sb.to_string())
    }
    None => ()
  }
}

///|
/// Side-effect-free byte read for debuggers and memory viewers. Only
/// DRAM is readable (device registers can have read side effects, e.g.
/// UART RBR); returns -1 outside DRAM.
pub fn Machine::peek8(self : Machine, addr : UInt) -> Int {
  match self.ram_off(addr, 1) {
    Some(off) => self.ram.read8(off).reinterpret_as_int()
    None => -1
  }
}

///|
/// Side-effect-free CSR read for debuggers (CSR reads have no side
/// effects in this machine). Returns None for unimplemented CSRs
/// instead of trapping.
pub fn Machine::csr_peek(self : Machine, addr : Int) -> UInt? {
  try {
    Some(self.csr.read(addr, self.clint.mtime))
  } catch {
    _ => None
  }
}
