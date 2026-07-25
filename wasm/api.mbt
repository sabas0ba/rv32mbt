///|
/// wasm-gc export surface. Every signature uses only Int so the module
/// can be driven from any wasm host without GC-type marshalling: images
/// are staged byte by byte, UART output is drained byte by byte.
priv struct WasmVm {
  mut machine : @core.Machine?
  mut ram_size : Int
  staging : Array[Byte]
  output : Array[Byte]
  mut read : Int
  trace_buf : Array[Byte]
  mut trace_read : Int
}

///|
let vm : WasmVm = {
  machine: None,
  ram_size: 0,
  staging: [],
  output: [],
  read: 0,
  trace_buf: [],
  trace_read: 0,
}

///|
/// Create a machine with `ram_mb` MiB of DRAM.
pub fn vm_create(ram_mb : Int) -> Unit {
  let m = @core.Machine::new(ram_size=ram_mb * 1024 * 1024)
  m.uart().set_tx(b => vm.output.push(b))
  m.set_trace_sink(line => {
    // trace lines are ASCII; buffer them byte-wise for vm_trace_take_byte
    for c in line {
      vm.trace_buf.push((c.to_int() & 0x7F).to_byte())
    }
    vm.trace_buf.push(10)
  })
  vm.machine = Some(m)
  vm.ram_size = ram_mb * 1024 * 1024
  vm.staging.clear()
  vm.output.clear()
  vm.read = 0
  vm.trace_buf.clear()
  vm.trace_read = 0
}

///|
/// Discard staged image bytes.
pub fn vm_stage_clear() -> Unit {
  vm.staging.clear()
}

///|
/// Append one byte (low 8 bits of `b`) to the staged image.
pub fn vm_stage_push(b : Int) -> Unit {
  vm.staging.push((b & 0xFF).to_byte())
}

///|
/// Parse the staged bytes as ELF32 and load it. Returns 0 on success,
/// -1 on parse error or if no machine exists.
pub fn vm_load_elf_staged() -> Int {
  match vm.machine {
    Some(m) =>
      try {
        m.load_elf(@core.parse_elf(Bytes::from_array(vm.staging)))
        vm.staging.clear()
        0
      } catch {
        _ => -1
      }
    None => -1
  }
}

///|
/// Load the staged bytes as a flat binary at DRAM base and point pc there.
pub fn vm_load_bin_staged() -> Unit {
  match vm.machine {
    Some(m) => {
      m.load_image(@core.DRAM_BASE, Bytes::from_array(vm.staging))
      m.set_pc(@core.DRAM_BASE)
      vm.staging.clear()
    }
    None => ()
  }
}

///|
/// Load the staged bytes as a device tree blob into the top 2 MiB of
/// DRAM and set the Linux boot registers (a0 = hartid 0, a1 = DTB
/// address). Returns 0 on success, -1 if the blob does not fit.
pub fn vm_load_dtb_staged() -> Int {
  match vm.machine {
    Some(m) => {
      let reserve = 0x200000
      if vm.staging.length() > reserve || vm.ram_size <= reserve {
        return -1
      }
      let addr = @core.DRAM_BASE +
        (vm.ram_size - reserve).reinterpret_as_uint()
      m.load_image(addr, Bytes::from_array(vm.staging))
      m.set_reg(10, 0)
      m.set_reg(11, addr)
      vm.staging.clear()
      0
    }
    None => -1
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
/// 1 if the machine has halted (or none exists), else 0.
pub fn vm_halted() -> Int {
  match vm.machine {
    Some(m) => if m.halted() { 1 } else { 0 }
    None => 1
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
/// Current pc as a raw 32-bit value (reinterpreted as Int).
pub fn vm_pc() -> Int {
  match vm.machine {
    Some(m) => m.pc().reinterpret_as_int()
    None => 0
  }
}

///|
/// Feed one byte of input to UART0 RX.
pub fn vm_push_input(b : Int) -> Unit {
  match vm.machine {
    Some(m) => m.uart().push_rx((b & 0xFF).to_byte())
    None => ()
  }
}

///|
/// Take one byte of buffered UART0 output, or -1 if none is pending.
/// A read cursor avoids shifting the buffer on every call; the buffer
/// is reclaimed once fully drained.
pub fn vm_take_byte() -> Int {
  if vm.read >= vm.output.length() {
    vm.output.clear()
    vm.read = 0
    -1
  } else {
    let b = vm.output[vm.read].to_int()
    vm.read += 1
    b
  }
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
/// Read general-purpose register `i` (0..31); raw 32-bit value
/// reinterpreted as Int.
pub fn vm_reg(i : Int) -> Int {
  match vm.machine {
    Some(m) => m.reg(i).reinterpret_as_int()
    None => 0
  }
}

///|
/// Side-effect-free byte read; `addr` is the raw 32-bit address
/// reinterpreted as Int. Returns the byte, or -1 outside DRAM.
pub fn vm_peek(addr : Int) -> Int {
  match vm.machine {
    Some(m) => m.peek8(addr.reinterpret_as_uint())
    None => -1
  }
}

///|
/// Read a CSR by address; raw 32-bit value reinterpreted as Int.
/// Returns 0 for unimplemented CSRs (probe with vm_csr_ok first).
pub fn vm_csr(addr : Int) -> Int {
  match vm.machine {
    Some(m) =>
      match m.csr_peek(addr) {
        Some(v) => v.reinterpret_as_int()
        None => 0
      }
    None => 0
  }
}

///|
/// 1 if the CSR at `addr` is implemented, else 0.
pub fn vm_csr_ok(addr : Int) -> Int {
  match vm.machine {
    Some(m) => if m.csr_peek(addr) is Some(_) { 1 } else { 0 }
    None => 0
  }
}

///|
/// Toggle the spike-style commit log (nonzero = on).
pub fn vm_set_trace(on : Int) -> Unit {
  match vm.machine {
    Some(m) => m.set_trace(on != 0)
    None => ()
  }
}

///|
/// Take one byte of buffered trace text (UTF-8/ASCII, lines end with
/// '\n'), or -1 if none is pending.
pub fn vm_trace_take_byte() -> Int {
  if vm.trace_read >= vm.trace_buf.length() {
    vm.trace_buf.clear()
    vm.trace_read = 0
    -1
  } else {
    let b = vm.trace_buf[vm.trace_read].to_int()
    vm.trace_read += 1
    b
  }
}
