///|
/// Machine-level trap. Raised by memory access and instruction execution,
/// caught by the step loop which redirects control to the trap vector.
pub(all) suberror Trap {
  Trap(cause~ : Int, tval~ : UInt)
}

///|
/// Exception cause codes (mcause, interrupt bit clear).
/// RISC-V Privileged Architecture, Table "Machine cause register".
pub const CAUSE_MISALIGNED_FETCH : Int = 0

///|
pub const CAUSE_FETCH_ACCESS : Int = 1

///|
pub const CAUSE_ILLEGAL_INSTRUCTION : Int = 2

///|
pub const CAUSE_BREAKPOINT : Int = 3

///|
pub const CAUSE_MISALIGNED_LOAD : Int = 4

///|
pub const CAUSE_LOAD_ACCESS : Int = 5

///|
pub const CAUSE_MISALIGNED_STORE : Int = 6

///|
pub const CAUSE_STORE_ACCESS : Int = 7

///|
pub const CAUSE_USER_ECALL : Int = 8

///|
pub const CAUSE_MACHINE_ECALL : Int = 11

///|
/// Interrupt cause codes (mcause, interrupt bit set).
pub const IRQ_M_SOFT : Int = 3

///|
pub const IRQ_M_TIMER : Int = 7

///|
pub const IRQ_M_EXT : Int = 11
