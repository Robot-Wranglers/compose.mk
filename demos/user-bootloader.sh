#!/usr/bin/env bash
# demos/user-bootloader.sh: an example USER bootloader for compose.mk.
#
#   Point CMK_BOOTLOADER at this file and compose.mk's supervisor will `source` it FIRST --
#   at BOOT, before the trampoline runs the program -- the single user extension point for
#   the supervisor.  It runs in the supervisor's own shell (NOT a subshell), so at boot it
#   sees the pre-run state ($_targets, $MAKE_SUPER, $_make_) and can SET UP the run; to reach
#   the END of the run (where $st, the recovered exit code, is final) it registers an `EXIT`
#   trap.  It must NOT trap INT/TERM (that clobbers the supervisor's own SIGINT handling).
#
#   USAGE:
#     CMK_BOOTLOADER=demos/user-bootloader.sh CMK_SUPERVISOR=1 ./compose.mk flux.ok
#
#   Keep user bootloaders PORTABLE (Linux / OSX / Alpine-busybox): POSIX shell + tools that
#   exist everywhere.  This one just proves it loaded at both ends of the run.
echo "user-bootloader: boot (targets=[${_targets:-}])"
trap 'echo "user-bootloader: exit (st=${st:-?})"' EXIT
