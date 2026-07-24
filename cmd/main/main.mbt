///|
/// Native CLI frontend.
///
/// Usage:
///   rv32mbt <image.elf> [options]
///   rv32mbt --bin <image.bin> [options]
///
/// Options:
///   --bin              treat the image as a flat binary loaded at --load-addr
///   --load-addr ADDR   load address for --bin (default 0x80000000)
///   --pc ADDR          initial pc (default: ELF entry, or --load-addr)
///   --max-steps N      stop after N instructions (default: unlimited)
///   --quiet            suppress the exit status line
///
/// UART0 output goes to stdout; stdin (raw mode) feeds UART0 RX.
fn usage() -> Unit {
  println("usage: rv32mbt [--bin] [--load-addr A] [--pc A] [--max-steps N] [--quiet] <image>")
}

///|
fn parse_uint(s : String) -> UInt? {
  let (digits, base) = if s.has_prefix("0x") || s.has_prefix("0X") {
    (s[2:], 16U)
  } else {
    (s[:], 10U)
  }
  if digits.length() == 0 {
    return None
  }
  let mut acc : UInt = 0
  for c in digits {
    let d = if c >= '0' && c <= '9' {
      c.to_int() - 48
    } else if c >= 'a' && c <= 'f' {
      c.to_int() - 87
    } else if c >= 'A' && c <= 'F' {
      c.to_int() - 55
    } else {
      return None
    }
    if d.reinterpret_as_uint() >= base {
      return None
    }
    acc = acc * base + d.reinterpret_as_uint()
  }
  Some(acc)
}

///|
fn main {
  let args = cli_args()
  let mut image_path : String? = None
  let mut flat_bin = false
  let mut load_addr : UInt = @core.DRAM_BASE
  let mut pc_override : UInt? = None
  let mut max_steps : Int64 = -1
  let mut quiet = false
  let mut i = 1 // skip argv[0]
  while i < args.length() {
    let a = args[i]
    if a == "--bin" {
      flat_bin = true
    } else if a == "--quiet" {
      quiet = true
    } else if a == "--load-addr" && i + 1 < args.length() {
      i += 1
      match parse_uint(args[i]) {
        Some(v) => load_addr = v
        None => {
          usage()
          exit_process(2)
        }
      }
    } else if a == "--pc" && i + 1 < args.length() {
      i += 1
      match parse_uint(args[i]) {
        Some(v) => pc_override = Some(v)
        None => {
          usage()
          exit_process(2)
        }
      }
    } else if a == "--max-steps" && i + 1 < args.length() {
      i += 1
      match parse_uint(args[i]) {
        Some(v) => max_steps = v.to_uint64().reinterpret_as_int64()
        None => {
          usage()
          exit_process(2)
        }
      }
    } else if a == "--help" {
      usage()
      exit_process(0)
    } else {
      image_path = Some(a)
    }
    i += 1
  }
  let path = match image_path {
    Some(p) => p
    None => {
      usage()
      exit_process(2)
      return
    }
  }
  let data = match read_file(path) {
    Some(d) => d
    None => {
      println("rv32mbt: cannot read \{path}")
      exit_process(1)
      return
    }
  }
  let m = @core.Machine::new()
  if flat_bin {
    m.load_image(load_addr, data)
    m.set_pc(load_addr)
  } else {
    match (try? @core.parse_elf(data)) {
      Ok(img) => m.load_elf(img)
      Err(e) => {
        println("rv32mbt: \{path}: \{e}")
        exit_process(1)
        return
      }
    }
  }
  match pc_override {
    Some(pc) => m.set_pc(pc)
    None => ()
  }
  m.uart().set_tx(b => put_byte(b.to_int()))
  term_raw_begin()
  let batch = 65536
  let mut executed : Int64 = 0
  while !m.halted() {
    let n = if max_steps >= 0 {
      let rest = max_steps - executed
      if rest <= 0 {
        break
      }
      if rest < batch.to_int64() {
        rest.to_int()
      } else {
        batch
      }
    } else {
      batch
    }
    executed += m.run(n).to_int64()
    // poll host input into UART RX
    let mut c = get_byte()
    while c >= 0 {
      m.uart().push_rx(c.to_byte())
      c = get_byte()
    }
  }
  term_raw_end()
  if !quiet {
    println("")
    println("[rv32mbt] halted, exit=\{m.exit_code()}, steps=\{executed}")
  }
  exit_process(m.exit_code())
}
