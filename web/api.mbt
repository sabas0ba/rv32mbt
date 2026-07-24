///|
/// Browser (js backend) API. A single machine instance is held in module
/// state; UART output is buffered and drained by the host page.
struct WebVm {
  mut machine : @core.Machine?
  output : Array[Byte]
}

///|
let vm : WebVm = { machine: None, output: [] }

///|
/// Create a machine with `ram_mb` MiB of DRAM.
pub fn vm_create(ram_mb : Int) -> Unit {
  let m = @core.Machine::new(ram_size=ram_mb * 1024 * 1024)
  m.uart().set_tx(b => vm.output.push(b))
  vm.machine = Some(m)
}

///|
/// Load an ELF image; returns the entry point, or -1.0 on parse error.
pub fn vm_load_elf(data : Bytes) -> Double {
  match vm.machine {
    Some(m) =>
      match (try? @core.parse_elf(data)) {
        Ok(img) => {
          m.load_elf(img)
          m.pc().to_uint64().to_double()
        }
        Err(_) => -1.0
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
