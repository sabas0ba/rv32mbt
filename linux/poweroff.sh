#!/bin/sh
# PID 1 is the init script's shell, not busybox init, so the plain
# poweroff applet (which signals init) cannot work; force the direct
# reboot(2) path.
exec /bin/busybox poweroff -f
