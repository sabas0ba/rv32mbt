///|
/// wasm-gc export surface. Every signature uses only Int so the module
/// can be driven from any wasm host without GC-type marshalling: images
/// are staged byte by byte, UART output is drained byte by byte.
priv struct WasmVm {
  mut machine : @core.Machine?
  staging : Array[Byte]
  output : Array[Byte]
  mut read : Int
}

///|
let vm : WasmVm = { machine: None, staging: [], output: [], read: 0 }

///|
/// Create a machine with `ram_mb` MiB of DRAM.
pub fn vm_create(ram_mb : Int) -> Unit {
  let m = @core.Machine::new(ram_size=ram_mb * 1024 * 1024)
  m.uart().set_tx(b => vm.output.push(b))
  vm.machine = Some(m)
  vm.staging.clear()
  vm.output.clear()
  vm.read = 0
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
