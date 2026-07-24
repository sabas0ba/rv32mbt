///|
/// Minimal ELF32 (little-endian) loader for RISC-V executables.
pub(all) suberror ElfError {
  ElfError(String)
}

///|
/// A loadable segment: physical address and file contents
/// (zero fill up to memsz is applied by the caller via `fill`).
pub struct ElfSegment {
  paddr : UInt
  data : Bytes
  memsz : Int
}

///|
pub struct ElfImage {
  entry : UInt
  segments : Array[ElfSegment]
  /// Address of the `tohost` symbol (riscv-tests HTIF), 0 if absent.
  tohost : UInt
}

///|
fn r8(d : Bytes, off : Int) -> Int {
  d[off].to_int()
}

///|
fn r16(d : Bytes, off : Int) -> Int {
  r8(d, off) | (r8(d, off + 1) << 8)
}

///|
fn r32(d : Bytes, off : Int) -> UInt {
  (r8(d, off) | (r8(d, off + 1) << 8) | (r8(d, off + 2) << 16) | (r8(d, off + 3) << 24)).reinterpret_as_uint()
}

///|
/// Parse an ELF32 executable. Checks: magic, 32-bit, little-endian,
/// machine EM_RISCV (243).
pub fn parse_elf(data : Bytes) -> ElfImage raise ElfError {
  if data.length() < 52 {
    raise ElfError("file too small for an ELF header")
  }
  if !(data[0] == 0x7F && data[1] == b'E' && data[2] == b'L' && data[3] == b'F') {
    raise ElfError("bad ELF magic")
  }
  if r8(data, 4) != 1 {
    raise ElfError("not ELF32")
  }
  if r8(data, 5) != 1 {
    raise ElfError("not little-endian")
  }
  if r16(data, 18) != 243 {
    raise ElfError("machine is not EM_RISCV")
  }
  let entry = r32(data, 24)
  let phoff = r32(data, 28).reinterpret_as_int()
  let phentsize = r16(data, 42)
  let phnum = r16(data, 44)
  let segments : Array[ElfSegment] = []
  for i in 0..<phnum {
    let ph = phoff + i * phentsize
    if ph + 32 > data.length() {
      raise ElfError("program header out of range")
    }
    let p_type = r32(data, ph)
    if p_type != 1 { // PT_LOAD
      continue
    }
    let p_offset = r32(data, ph + 4).reinterpret_as_int()
    let p_paddr = r32(data, ph + 12)
    let p_filesz = r32(data, ph + 16).reinterpret_as_int()
    let p_memsz = r32(data, ph + 20).reinterpret_as_int()
    if p_offset + p_filesz > data.length() {
      raise ElfError("segment data out of range")
    }
    segments.push({
      paddr: p_paddr,
      data: data[p_offset:p_offset + p_filesz].to_bytes(),
      memsz: p_memsz,
    })
  }
  let tohost = find_symbol(data, "tohost")
  { entry, segments, tohost }
}

///|
/// Locate a symbol address via .symtab/.strtab; returns 0 when not found.
fn find_symbol(data : Bytes, name : String) -> UInt {
  let shoff = r32(data, 32).reinterpret_as_int()
  let shentsize = r16(data, 46)
  let shnum = r16(data, 48)
  if shoff == 0 {
    return 0
  }
  for i in 0..<shnum {
    let sh = shoff + i * shentsize
    if sh + 40 > data.length() {
      return 0
    }
    let sh_type = r32(data, sh + 4).reinterpret_as_int()
    if sh_type != 2 { // SHT_SYMTAB
      continue
    }
    let sym_off = r32(data, sh + 16).reinterpret_as_int()
    let sym_size = r32(data, sh + 20).reinterpret_as_int()
    let sh_link = r32(data, sh + 24).reinterpret_as_int()
    let entsize = r32(data, sh + 36).reinterpret_as_int()
    if entsize == 0 {
      continue
    }
    // string table section header
    let str_sh = shoff + sh_link * shentsize
    let str_off = r32(data, str_sh + 16).reinterpret_as_int()
    let count = sym_size / entsize
    for s in 0..<count {
      let sym = sym_off + s * entsize
      let name_idx = r32(data, sym).reinterpret_as_int()
      if name_idx == 0 {
        continue
      }
      if symbol_name_equals(data, str_off + name_idx, name) {
        return r32(data, sym + 4) // st_value
      }
    }
  }
  0
}

///|
fn symbol_name_equals(data : Bytes, off : Int, name : String) -> Bool {
  for i in 0..<name.length() {
    if off + i >= data.length() {
      return false
    }
    if data[off + i].to_int() != name[i].to_int() {
      return false
    }
  }
  off + name.length() < data.length() && data[off + name.length()] == 0
}

///|
/// Load a parsed ELF image into machine memory and set pc/tohost.
pub fn Machine::load_elf(self : Machine, img : ElfImage) -> Unit {
  for seg in img.segments {
    if seg.data.length() > 0 {
      self.load_image(seg.paddr, seg.data)
    }
    // memsz > filesz zero-fill: DRAM is zero-initialized, so nothing to do
  }
  self.set_pc(img.entry)
  if img.tohost != 0 {
    self.set_tohost(img.tohost)
  }
}
