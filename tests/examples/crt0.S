/* Startup code for the bare-metal C examples: set up the stack, zero
 * .bss, call main, then report main's return value through the
 * sifive_test finisher (0 -> PASS, nonzero -> FAIL with code). */
.section .text.init
.globl _start
_start:
        la      sp, __stack_top
        la      a0, __bss_start
        la      a1, __bss_end
1:      bgeu    a0, a1, 2f
        sw      zero, 0(a0)
        addi    a0, a0, 4
        j       1b
2:      call    main
        lui     t0, 0x100            /* sifive_test base */
        beqz    a0, 3f
        slli    a0, a0, 16           /* FINISHER_FAIL: (code << 16) | 0x3333 */
        li      t1, 0x3333
        or      a0, a0, t1
        j       4f
3:      li      a0, 0x5555           /* FINISHER_PASS */
4:      sw      a0, 0(t0)
5:      j       5b
