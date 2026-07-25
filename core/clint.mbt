///|
/// CLINT (core-local interruptor), register layout as in the QEMU virt
/// machine (SiFive CLINT / ACLINT MTIMER+MSWI): base 0x0200_0000,
/// msip hart0 at +0x0, mtimecmp hart0 at +0x4000, mtime at +0xBFF8.
/// Single hart, 32-bit accesses only.
pub struct Clint {
  mut msip : Bool
  mut mtimecmp : UInt64
  mut mtime : UInt64
}

///|
pub fn Clint::new() -> Clint {
  { msip: false, mtimecmp: 0xFFFFFFFFFFFFFFFFUL, mtime: 0 }
}

///|
/// Power-on state (warm reset).
pub fn Clint::reset(self : Clint) -> Unit {
  self.msip = false
  self.mtimecmp = 0xFFFFFFFFFFFFFFFFUL
  self.mtime = 0
}

///|
pub fn Clint::tick(self : Clint, n : Int) -> Unit {
  self.mtime = self.mtime + n.to_uint64()
}

///|
pub fn Clint::timer_pending(self : Clint) -> Bool {
  self.mtime >= self.mtimecmp
}

///|
pub fn Clint::read32(self : Clint, off : Int) -> UInt {
  match off {
    0x0000 => if self.msip { 1 } else { 0 }
    0x4000 => self.mtimecmp.to_uint()
    0x4004 => (self.mtimecmp >> 32).to_uint()
    0xBFF8 => self.mtime.to_uint()
    0xBFFC => (self.mtime >> 32).to_uint()
    _ => 0
  }
}

///|
pub fn Clint::write32(self : Clint, off : Int, value : UInt) -> Unit {
  match off {
    0x0000 => self.msip = (value & 1) != 0
    0x4000 =>
      self.mtimecmp = (self.mtimecmp & 0xFFFFFFFF00000000UL) |
        value.to_uint64()
    0x4004 =>
      self.mtimecmp = (self.mtimecmp & 0xFFFFFFFFUL) |
        (value.to_uint64() << 32)
    0xBFF8 =>
      self.mtime = (self.mtime & 0xFFFFFFFF00000000UL) | value.to_uint64()
    0xBFFC =>
      self.mtime = (self.mtime & 0xFFFFFFFFUL) | (value.to_uint64() << 32)
    _ => ()
  }
}
