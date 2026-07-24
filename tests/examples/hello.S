/* Bare-metal smoke test: print via UART0 (0x1000_0000), then exit via
 * the sifive_test finisher (0x0010_0000). Runs unmodified on
 * qemu-system-riscv32 -M virt and on rv32mbt. */
.section .text.init
.globl _start
_start:
        lui     a0, 0x10000          /* UART0 base */
        la      a1, msg
1:      lbu     a2, 0(a1)
        beqz    a2, 2f
        sb      a2, 0(a0)
        addi    a1, a1, 1
        j       1b
2:      lui     a0, 0x100            /* sifive_test base */
        li      a1, 0x5555           /* FINISHER_PASS */
        sw      a1, 0(a0)
3:      j       3b

.section .data
msg:    .asciz  "hello from rv32mbt\n"
