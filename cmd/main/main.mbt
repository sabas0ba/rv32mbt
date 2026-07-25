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
///   --trace            spike-style commit log on stderr
///   --dtb FILE         load a DTB near the top of DRAM and pass the
///                      Linux boot registers (a0 = hartid, a1 = &dtb)
///
/// UART0 output goes to stdout; stdin (raw mode) feeds UART0 RX.
fn usage() -> Unit {
  println(
    "usage: rv32mbt [--bin] [--load-addr A] [--pc A] [--max-steps N] [--quiet] [--trace] [--dtb FILE] <image>",
  )
}

///|
/// DRAM size used by the CLI machine (must match linux/rv32mbt.dts).
const RAM_MB : Int = 128

///|
/// The DTB is placed in the top 2 MiB of DRAM, away from the kernel
/// image loaded at the DRAM base (QEMU virt places it at the end of
/// RAM as well).
const DTB_RESERVE : UInt = 0x200000

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
  let mut trace = false
  let mut dtb_path : String? = None
  let mut i = 1 // skip argv[0]
  while i < args.length() {
    let a = args[i]
    if a == "--bin" {
      flat_bin = true
    } else if a == "--quiet" {
      quiet = true
    } else if a == "--trace" {
      trace = true
    } else if a == "--dtb" && i + 1 < args.length() {
      i += 1
      dtb_path = Some(args[i])
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
    try m.load_elf(@core.parse_elf(data)) catch {
      e => {
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
  match dtb_path {
    Some(p) => {
      let dtb = match read_file(p) {
        Some(d) => d
        None => {
          println("rv32mbt: cannot read \{p}")
          exit_process(1)
          return
        }
      }
      if dtb.length().reinterpret_as_uint() > DTB_RESERVE {
        println("rv32mbt: dtb larger than \{DTB_RESERVE} bytes")
        exit_process(1)
        return
      }
      let dtb_addr = @core.DRAM_BASE +
        (RAM_MB * 1024 * 1024).reinterpret_as_uint() -
        DTB_RESERVE
      m.load_image(dtb_addr, dtb)
      m.set_reg(10, 0) // a0 = hartid
      m.set_reg(11, dtb_addr) // a1 = device tree blob
    }
    None => ()
  }
  m.uart().set_tx(b => put_byte(b.to_int()))
  if trace {
    m.set_trace(true)
    m.set_trace_sink(line => eput_line(line))
  }
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
