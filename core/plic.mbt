///|
/// PLIC (platform-level interrupt controller), register layout as in the
/// QEMU virt machine: base 0x0C00_0000, priority at +0x0 (4 bytes per
/// source), pending at +0x1000, enable for context 0 at +0x2000
/// (stride 0x80), threshold/claim for context 0 at +0x20_0000
/// (stride 0x1000). Context 0 is hart 0 M-mode; sources 1..31 are
/// modeled (UART0 is source 10). 32-bit accesses only.
pub struct Plic {
  priority : FixedArray[UInt] // index = source, [0] unused
  mut pending : UInt // bitmask, bit = source id
  mut enable : UInt // context 0 enable bits, sources 0..31
  mut threshold : UInt
  mut claimed : UInt // sources claimed but not yet completed
}

///|
const PLIC_PRIORITY_BASE : Int = 0x0

///|
const PLIC_PENDING_BASE : Int = 0x1000

///|
const PLIC_ENABLE_BASE : Int = 0x2000

///|
const PLIC_CONTEXT_BASE : Int = 0x200000

///|
pub fn Plic::new() -> Plic {
  {
    priority: FixedArray::make(32, 0),
    pending: 0,
    enable: 0,
    threshold: 0,
    claimed: 0,
  }
}

///|
/// Latch level-triggered inputs. `levels` is a bitmask of asserted
/// sources. A source whose claim is outstanding is gated off until
/// completion.
pub fn Plic::update(self : Plic, levels : UInt) -> Unit {
  self.pending = self.pending | (levels & self.claimed.lnot())
}

///|
/// External interrupt notification toward the hart (mip.MEIP): some
/// pending+enabled source has priority above the threshold.
pub fn Plic::eip(self : Plic) -> Bool {
  let candidates = self.pending & self.enable
  for src in 1..<32 {
    if ((candidates >> src) & 1) != 0 && self.priority[src] > self.threshold {
      break true
    }
  } nobreak {
    false
  }
}

///|
/// Claim: return the highest-priority pending+enabled source (0 if none)
/// and clear its pending bit.
fn Plic::claim(self : Plic) -> UInt {
  let candidates = self.pending & self.enable
  let mut best = 0
  let mut best_prio : UInt = 0
  for src in 1..<32 {
    if ((candidates >> src) & 1) != 0 && self.priority[src] > best_prio {
      best = src
      best_prio = self.priority[src]
    }
  }
  if best != 0 {
    let bit = 1U << best
    self.pending = self.pending & bit.lnot()
    self.claimed = self.claimed | bit
  }
  best.reinterpret_as_uint()
}

///|
fn Plic::complete(self : Plic, src : UInt) -> Unit {
  let s = src.reinterpret_as_int()
  if s >= 1 && s < 32 {
    self.claimed = self.claimed & (1U << s).lnot()
  }
}

///|
pub fn Plic::read32(self : Plic, off : Int) -> UInt {
  if off >= PLIC_PRIORITY_BASE && off < PLIC_PRIORITY_BASE + 32 * 4 {
    self.priority[off / 4]
  } else if off == PLIC_PENDING_BASE {
    self.pending
  } else if off == PLIC_ENABLE_BASE {
    self.enable
  } else if off == PLIC_CONTEXT_BASE {
    self.threshold
  } else if off == PLIC_CONTEXT_BASE + 4 {
    self.claim()
  } else {
    0
  }
}

///|
pub fn Plic::write32(self : Plic, off : Int, value : UInt) -> Unit {
  if off >= PLIC_PRIORITY_BASE && off < PLIC_PRIORITY_BASE + 32 * 4 {
    let src = off / 4
    if src != 0 {
      self.priority[src] = value & 0x7 // 3 priority bits on virt
    }
  } else if off == PLIC_ENABLE_BASE {
    self.enable = value & 0xFFFFFFFE // source 0 does not exist
  } else if off == PLIC_CONTEXT_BASE {
    self.threshold = value & 0x7
  } else if off == PLIC_CONTEXT_BASE + 4 {
    self.complete(value)
  }
}
