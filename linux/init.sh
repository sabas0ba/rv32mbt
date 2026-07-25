#!/bin/sh
# rv32mbt initramfs /init: mount the pseudo filesystems and keep an
# interactive shell on the console. the shell on nommu re-executes itself
# through /proc/self/exe for external commands and standalone applets,
# so /proc must be mounted before the first command runs.
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
echo
echo "rv32mbt: BusyBox v1.36.1 userspace (nommu RV32, hush). Type 'help'."
while :; do
	/bin/sh
	echo "(shell exited; restarting)"
done
