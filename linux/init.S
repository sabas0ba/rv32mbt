/* Minimal PID 1 for the userspace bring-up: write a banner to stdout
 * and power off via reboot(2). Freestanding (no libc) and strictly
 * PC-relative so the binfmt_elf_fdpic loader can place it at any
 * address without processing relocations. */
	.text
	.globl _start
_start:
	li	a0, 1                  /* fd = stdout */
	lla	a1, msg                /* auipc+addi; no GOT even under PIE */
	lla	a2, msg_end            /* length as a register difference:   */
	sub	a2, a2, a1             /* li with a symbol difference is not */
	                               /* assemblable under PIC              */
	li	a7, 64                 /* __NR_write */
	ecall

	li	a0, 0xfee1dead         /* LINUX_REBOOT_MAGIC1 */
	li	a1, 0x28121969         /* LINUX_REBOOT_MAGIC2 */
	li	a2, 0x4321fedc         /* LINUX_REBOOT_CMD_POWER_OFF */
	mv	a3, zero
	li	a7, 142                /* __NR_reboot */
	ecall
1:	j	1b

	.section .rodata
msg:	.ascii	"rv32mbt: hello from userspace (PID 1)\n"
msg_end:
