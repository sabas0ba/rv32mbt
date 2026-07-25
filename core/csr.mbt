///|
/// M-mode CSR file. Only the machine level is implemented; the hart always
/// executes in M-mode (nommu Linux, CONFIG_RISCV_M_MODE).
pub struct Csr {
  mut mstatus : UInt
  mut mie : UInt
  mut mip : UInt
  mut mtvec : UInt
  mut mscratch : UInt
  mut mepc : UInt
  mut mcause : UInt
  mut mtval : UInt
  mut mcycle : UInt64
  mut minstret : UInt64
}

///|
/// CSR addresses.
const CSR_MSTATUS : Int = 0x300

///|
const CSR_MISA : Int = 0x301

///|
const CSR_MIE : Int = 0x304

///|
const CSR_MTVEC : Int = 0x305

///|
const CSR_MCOUNTEREN : Int = 0x306

///|
const CSR_MSTATUSH : Int = 0x310

///|
const CSR_MCOUNTINHIBIT : Int = 0x320

///|
const CSR_MSCRATCH : Int = 0x340

///|
const CSR_MEPC : Int = 0x341

///|
const CSR_MCAUSE : Int = 0x342

///|
const CSR_MTVAL : Int = 0x343

///|
const CSR_MIP : Int = 0x344

///|
const CSR_MCYCLE : Int = 0xB00

///|
const CSR_MINSTRET : Int = 0xB02

///|
const CSR_MCYCLEH : Int = 0xB80

///|
const CSR_MINSTRETH : Int = 0xB82

///|
const CSR_CYCLE : Int = 0xC00

///|
const CSR_TIME : Int = 0xC01

///|
const CSR_INSTRET : Int = 0xC02

///|
const CSR_CYCLEH : Int = 0xC80

///|
const CSR_TIMEH : Int = 0xC81

///|
const CSR_INSTRETH : Int = 0xC82

///|
const CSR_MVENDORID : Int = 0xF11

///|
const CSR_MARCHID : Int = 0xF12

///|
const CSR_MIMPID : Int = 0xF13

///|
const CSR_MHARTID : Int = 0xF14

///|
/// mstatus fields used by an M-mode-only hart.
const MSTATUS_MIE : UInt = 0x8

///|
const MSTATUS_MPIE : UInt = 0x80

///|
const MSTATUS_MPP : UInt = 0x1800

///|
/// Writable mstatus bits: MIE, MPIE. MPP is WARL over {U, M}: writes
/// of 3 keep M, anything else becomes U (handled in Csr::write).
const MSTATUS_WMASK : UInt = MSTATUS_MIE | MSTATUS_MPIE

///|
/// misa: MXL=32 (bit 30), extensions I, M, A, C.
const MISA_VALUE : UInt = 0x40000000 |
  (1U << 8) | // I
  (1U << 12) | // M
  (1U << 0) | // A
  (1U << 2) // C

///|
/// Writable mie/mip bits: MSIE/MTIE/MEIE (software, timer, external).
const MIE_WMASK : UInt = (1U << 3) | (1U << 7) | (1U << 11)

///|
pub fn Csr::new() -> Csr {
  {
    mstatus: MSTATUS_MPP, // MPP=3
    mie: 0,
    mip: 0,
    mtvec: 0,
    mscratch: 0,
    mepc: 0,
    mcause: 0,
    mtval: 0,
    mcycle: 0,
    minstret: 0,
  }
}

///|
/// Read a CSR. `mtime` is supplied by the caller because the time CSRs
/// mirror the CLINT mtime register.
pub fn Csr::read(self : Csr, addr : Int, mtime : UInt64) -> UInt raise Trap {
  match addr {
    CSR_MSTATUS => self.mstatus
    CSR_MISA => MISA_VALUE
    CSR_MIE => self.mie
    CSR_MTVEC => self.mtvec
    CSR_MCOUNTEREN => 0
    CSR_MSTATUSH => 0
    CSR_MCOUNTINHIBIT => 0
    CSR_MSCRATCH => self.mscratch
    CSR_MEPC => self.mepc
    CSR_MCAUSE => self.mcause
    CSR_MTVAL => self.mtval
    CSR_MIP => self.mip
    CSR_MCYCLE | CSR_CYCLE => self.mcycle.to_uint()
    CSR_MCYCLEH | CSR_CYCLEH => (self.mcycle >> 32).to_uint()
    CSR_MINSTRET | CSR_INSTRET => self.minstret.to_uint()
    CSR_MINSTRETH | CSR_INSTRETH => (self.minstret >> 32).to_uint()
    CSR_TIME => mtime.to_uint()
    CSR_TIMEH => (mtime >> 32).to_uint()
    CSR_MVENDORID | CSR_MARCHID | CSR_MIMPID | CSR_MHARTID => 0
    _ => raise Trap(cause=CAUSE_ILLEGAL_INSTRUCTION, tval=0)
  }
}

///|
/// Write a CSR. Read-only CSRs (addr[11:10] == 0b11) raise an illegal
/// instruction exception.
pub fn Csr::write(self : Csr, addr : Int, value : UInt) -> Unit raise Trap {
  if ((addr >> 10) & 0x3) == 0x3 {
    raise Trap(cause=CAUSE_ILLEGAL_INSTRUCTION, tval=0)
  }
  match addr {
    CSR_MSTATUS => {
      let mpp = if (value & MSTATUS_MPP) == MSTATUS_MPP { MSTATUS_MPP } else { 0 }
      self.mstatus = (value & MSTATUS_WMASK) | mpp
    }
    CSR_MISA => () // WARL, fixed
    CSR_MIE => self.mie = value & MIE_WMASK
    CSR_MTVEC => self.mtvec = value & 0xFFFFFFFD // mode: 0/1 only
    CSR_MCOUNTEREN | CSR_MSTATUSH | CSR_MCOUNTINHIBIT => ()
    CSR_MSCRATCH => self.mscratch = value
    CSR_MEPC => self.mepc = value & 0xFFFFFFFE // IALIGN=16 (C extension)
    CSR_MCAUSE => self.mcause = value
    CSR_MTVAL => self.mtval = value
    CSR_MIP => () // MSIP/MTIP/MEIP are set by devices, not software
    CSR_MCYCLE =>
      self.mcycle = (self.mcycle & 0xFFFFFFFF00000000UL) | value.to_uint64()
    CSR_MCYCLEH =>
      self.mcycle = (self.mcycle & 0xFFFFFFFFUL) | (value.to_uint64() << 32)
    CSR_MINSTRET =>
      self.minstret = (self.minstret & 0xFFFFFFFF00000000UL) | value.to_uint64()
    CSR_MINSTRETH =>
      self.minstret = (self.minstret & 0xFFFFFFFFUL) | (value.to_uint64() << 32)
    _ => raise Trap(cause=CAUSE_ILLEGAL_INSTRUCTION, tval=0)
  }
}
