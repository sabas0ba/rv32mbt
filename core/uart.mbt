///|
/// 16550A-compatible UART, register-compatible with the QEMU virt machine's
/// UART0 (base 0x1000_0000, regshift=0, IRQ 10). Behavior follows the
/// public 16550 register specification; the transmitter is modeled as
/// infinitely fast (THR empties immediately).
pub struct Uart {
  mut tx : (Byte) -> Unit
  rx : Array[Byte]
  mut ier : UInt // interrupt enable
  mut fcr : UInt // FIFO control (write only)
  mut lcr : UInt // line control (bit7 = DLAB)
  mut mcr : UInt // modem control
  mut scr : UInt // scratch
  mut dll : UInt // divisor latch low
  mut dlm : UInt // divisor latch high
  mut thre_ip : Bool // THR-empty interrupt pending
}

///|
const IER_RDA : UInt = 0x1

///|
const IER_THRE : UInt = 0x2

///|
const LCR_DLAB : UInt = 0x80

///|
pub fn Uart::new() -> Uart {
  {
    tx: _b => (),
    rx: [],
    ier: 0,
    fcr: 0,
    lcr: 0,
    mcr: 0,
    scr: 0,
    dll: 0,
    dlm: 0,
    thre_ip: false,
  }
}

///|
pub fn Uart::set_tx(self : Uart, tx : (Byte) -> Unit) -> Unit {
  self.tx = tx
}

///|
/// Feed one received byte (from the host terminal / browser keyboard).
pub fn Uart::push_rx(self : Uart, b : Byte) -> Unit {
  self.rx.push(b)
}

///|
/// True once the guest has enabled the received-data interrupt.
/// Frontends use this to hold scripted input until a driver is
/// actually listening: pushing bytes earlier would let the 8250
/// probe's RX-flush reads consume them.
pub fn Uart::rx_listening(self : Uart) -> Bool {
  (self.ier & IER_RDA) != 0
}

///|
/// Highest-priority pending interrupt, encoded as the IIR[3:0] value.
/// 0b0001 = none, 0b0100 = received data available, 0b0010 = THR empty.
fn Uart::iir_low(self : Uart) -> UInt {
  if (self.ier & IER_RDA) != 0 && self.rx.length() > 0 {
    0x4
  } else if (self.ier & IER_THRE) != 0 && self.thre_ip {
    0x2
  } else {
    0x1
  }
}

///|
/// Interrupt line level toward the PLIC.
pub fn Uart::irq_pending(self : Uart) -> Bool {
  self.iir_low() != 0x1
}

///|
/// Byte read at register offset 0..7.
pub fn Uart::read(self : Uart, off : Int) -> UInt {
  match off {
    0 =>
      if (self.lcr & LCR_DLAB) != 0 {
        self.dll
      } else if self.rx.length() > 0 {
        let b = self.rx[0]
        let _ = self.rx.remove(0)
        b.to_int().reinterpret_as_uint()
      } else {
        0
      }
    1 => if (self.lcr & LCR_DLAB) != 0 { self.dlm } else { self.ier }
    2 => {
      let low = self.iir_low()
      if low == 0x2 {
        // reading IIR clears the THRE interrupt condition
        self.thre_ip = false
      }
      let fifo_bits : UInt = if (self.fcr & 0x1) != 0 { 0xC0 } else { 0 }
      fifo_bits | low
    }
    3 => self.lcr
    4 => self.mcr
    5 => {
      // LSR: TEMT | THRE always set; DR reflects the rx queue
      let dr : UInt = if self.rx.length() > 0 { 0x1 } else { 0 }
      0x60 | dr
    }
    6 => 0xB0 // MSR: CTS | DSR | DCD asserted
    7 => self.scr
    _ => 0
  }
}

///|
/// Byte write at register offset 0..7.
pub fn Uart::write(self : Uart, off : Int, value : UInt) -> Unit {
  let v = value & 0xFF
  match off {
    0 =>
      if (self.lcr & LCR_DLAB) != 0 {
        self.dll = v
      } else {
        (self.tx)((v.reinterpret_as_int() & 0xFF).to_byte())
        self.thre_ip = true
      }
    1 =>
      if (self.lcr & LCR_DLAB) != 0 {
        self.dlm = v
      } else {
        self.ier = v & 0xF
        if (self.ier & IER_THRE) != 0 {
          // enabling the THRE interrupt with an empty THR raises it
          self.thre_ip = true
        }
      }
    2 => self.fcr = v
    3 => self.lcr = v
    4 => self.mcr = v
    5 => () // LSR is read only
    6 => () // MSR is read only
    7 => self.scr = v
    _ => ()
  }
}
