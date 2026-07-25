///|
/// Browser (js backend) API. A single machine instance is held in module
/// state; UART output is buffered and drained by the host page.
priv struct WebVm {
  mut machine : @core.Machine?
  output : Array[Byte]
  trace_lines : Array[String]
}

///|
let vm : WebVm = { machine: None, output: [], trace_lines: [] }

///|
/// Create a machine with `ram_mb` MiB of DRAM.
pub fn vm_create(ram_mb : Int) -> Unit {
  let m = @core.Machine::new(ram_size=ram_mb * 1024 * 1024)
  m.uart().set_tx(b => vm.output.push(b))
  m.set_trace_sink(line => vm.trace_lines.push(line))
  vm.machine = Some(m)
  vm.output.clear()
  vm.trace_lines.clear()
}

///|
/// Load an ELF image; returns the entry point, or -1.0 on parse error.
pub fn vm_load_elf(data : Bytes) -> Double {
  match vm.machine {
    Some(m) =>
      try {
        m.load_elf(@core.parse_elf(data))
        m.pc().to_uint64().to_double()
      } catch {
        _ => -1.0
      }
    None => -1.0
  }
}

///|
/// Load a flat binary at DRAM base and point pc at it.
pub fn vm_load_bin(data : Bytes) -> Unit {
  match vm.machine {
    Some(m) => {
      m.load_image(@core.DRAM_BASE, data)
      m.set_pc(@core.DRAM_BASE)
    }
    None => ()
  }
}

///|
/// Execute up to `steps` instructions; returns the number executed.
pub fn vm_run(steps : Int) -> Int {
  match vm.machine {
    Some(m) => m.run(steps)
    None => 0
  }
}

///|
pub fn vm_halted() -> Bool {
  match vm.machine {
    Some(m) => m.halted()
    None => true
  }
}

///|
pub fn vm_exit_code() -> Int {
  match vm.machine {
    Some(m) => m.exit_code()
    None => 0
  }
}

///|
pub fn vm_pc() -> Double {
  match vm.machine {
    Some(m) => m.pc().to_uint64().to_double()
    None => 0.0
  }
}

///|
/// Feed one byte of keyboard input to UART0 RX.
pub fn vm_push_input(b : Int) -> Unit {
  match vm.machine {
    Some(m) => m.uart().push_rx((b & 0xFF).to_byte())
    None => ()
  }
}

///|
/// Drain buffered UART0 output.
pub fn vm_take_output() -> Bytes {
  let out = Bytes::from_array(vm.output)
  vm.output.clear()
  out
}

///|
/// Execute a single instruction; returns the number executed (0 or 1).
pub fn vm_step() -> Int {
  match vm.machine {
    Some(m) => m.run(1)
    None => 0
  }
}

///|
/// Read general-purpose register `i` (0..31) as a non-negative Double.
pub fn vm_reg(i : Int) -> Double {
  match vm.machine {
    Some(m) => m.reg(i).to_uint64().to_double()
    None => 0.0
  }
}

///|
/// Side-effect-free byte read for the memory viewer. `addr` is the raw
/// 32-bit address reinterpreted as Int (JS: `addr | 0`); returns the
/// byte value, or -1 outside DRAM.
pub fn vm_peek(addr : Int) -> Int {
  match vm.machine {
    Some(m) => m.peek8(addr.reinterpret_as_uint())
    None => -1
  }
}

///|
/// Read a CSR by address (e.g. 0x300 = mstatus) as a non-negative
/// Double, or -1.0 if the CSR is not implemented.
pub fn vm_csr(addr : Int) -> Double {
  match vm.machine {
    Some(m) =>
      match m.csr_peek(addr) {
        Some(v) => v.to_uint64().to_double()
        None => -1.0
      }
    None => -1.0
  }
}

///|
/// Toggle the spike-style commit log (drained by vm_take_trace).
pub fn vm_set_trace(on : Bool) -> Unit {
  match vm.machine {
    Some(m) => m.set_trace(on)
    None => ()
  }
}

///|
/// Drain buffered trace lines as one newline-joined string ("" if none).
pub fn vm_take_trace() -> String {
  if vm.trace_lines.is_empty() {
    return ""
  }
  let sb = StringBuilder::new()
  for line in vm.trace_lines {
    sb.write_string(line)
    sb.write_char('\n')
  }
  vm.trace_lines.clear()
  sb.to_string()
}
