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
  .text : { *(.text .text.*) }
  . = ALIGN(0x1000);
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) }
  .data : { *(.data .data.* .sdata .sdata.*) }
  .bss : {
    . = ALIGN(4);
    __bss_start = .;
    *(.bss .bss.* .sbss .sbss.*)
    *(COMMON)
    . = ALIGN(4);
    __bss_end = .;
  }
  _end = .;
}

/* Stack for the C examples' crt0; grows down from RAM base + 4 MiB.
 * The assembly-only riscv-tests do not reference it. */
PROVIDE(__stack_top = 0x80400000);
