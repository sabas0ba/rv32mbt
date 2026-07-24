/* Linker script for riscv-tests "p" environment on rv32 with ld.lld.
 * The upstream p/link.ld uses PHDRS FLAGS(SHF_*) symbols that lld does
 * not define; this script reproduces the required section layout with
 * default program headers instead. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
  . = 0x80000000;
  .text.init : { *(.text.init) }
  . = ALIGN(0x1000);
  .tohost : { *(.tohost) }
  . = ALIGN(0x1000);
  .text : { *(.text) }
  . = ALIGN(0x1000);
  .data : { *(.data) }
  .bss : { *(.bss) }
  _end = .;
}
