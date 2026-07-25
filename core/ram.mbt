///|
/// Flat little-endian DRAM. Offsets passed to the accessors are relative to
/// the DRAM base and must be bounds-checked by the caller (`Machine`).
pub struct Ram {
  mem : FixedArray[Byte]
  size : Int
}

///|
pub fn Ram::new(size : Int) -> Ram {
  { mem: FixedArray::make(size, 0), size }
}

///|
pub fn Ram::read8(self : Ram, off : Int) -> UInt {
  self.mem.unsafe_get(off).to_int().reinterpret_as_uint()
}

///|
pub fn Ram::read16(self : Ram, off : Int) -> UInt {
  let b0 = self.mem.unsafe_get(off).to_int()
  let b1 = self.mem.unsafe_get(off + 1).to_int()
  (b0 | (b1 << 8)).reinterpret_as_uint()
}

///|
pub fn Ram::read32(self : Ram, off : Int) -> UInt {
  let b0 = self.mem.unsafe_get(off).to_int()
  let b1 = self.mem.unsafe_get(off + 1).to_int()
  let b2 = self.mem.unsafe_get(off + 2).to_int()
  let b3 = self.mem.unsafe_get(off + 3).to_int()
  (b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)).reinterpret_as_uint()
}

///|
pub fn Ram::write8(self : Ram, off : Int, value : UInt) -> Unit {
  self.mem[off] = (value.reinterpret_as_int() & 0xFF).to_byte()
}

///|
pub fn Ram::write16(self : Ram, off : Int, value : UInt) -> Unit {
  let v = value.reinterpret_as_int()
  self.mem[off] = (v & 0xFF).to_byte()
  self.mem[off + 1] = ((v >> 8) & 0xFF).to_byte()
}

///|
pub fn Ram::write32(self : Ram, off : Int, value : UInt) -> Unit {
  let v = value.reinterpret_as_int()
  self.mem[off] = (v & 0xFF).to_byte()
  self.mem[off + 1] = ((v >> 8) & 0xFF).to_byte()
  self.mem[off + 2] = ((v >> 16) & 0xFF).to_byte()
  self.mem[off + 3] = ((v >> 24) & 0xFF).to_byte()
}

///|
/// Bulk load (program image, DTB).
pub fn Ram::load_bytes(self : Ram, off : Int, data : Bytes) -> Unit {
  for i in 0..<data.length() {
    self.mem[off + i] = data[i]
  }
}

///|
/// Zero all of DRAM (warm reset).
pub fn Ram::clear(self : Ram) -> Unit {
  self.mem.fill(0)
}
