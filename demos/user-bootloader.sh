#!/usr/bin/env bash
# demos/user-bootloader.sh: an example USER bootloader for compose.mk.
#
#   Point CMK_BOOTLOADER at this file and compose.mk's supervisor will `source` it FIRST --
#   at BOOT, before the trampoline runs the program -- the single user extension point for
#   the supervisor.  It runs in the supervisor's own shell (NOT a subshell), so at boot it
#   sees the pre-run state ($__argv__ -- the invocation's goals, $MAKE_SUPER, $_make_) and can SET
#   UP the run; to reach the END of the run (where $__exit_code__, the resolved exit code, is final) it
#   registers an `EXIT` trap.  It must NOT trap INT/TERM (that clobbers the supervisor's own
#   SIGINT handling).
#
#   OTHER REF FORMS: a plain <file> like this one is SOURCED as PREP (shares the shell, then
#   returns to the trampoline).  A CMK_BOOTLOADER entry may instead be `@<goal>` (run a target
#   in the running makefile, then continue) or `@<file>:<goal>` (EXEC `make -f <file> <goal>` --
#   a resolvable TARGET that TAKES OVER the run).  See demos/user-bootloader.mk for the
#   @<file>:<goal> takeover form (the shape a real backend like .cmk/beam.loader.mk uses).
#
#   USAGE:
#     CMK_BOOTLOADER=demos/user-bootloader.sh CMK_SUPERVISOR=1 ./compose.mk flux.ok
#
#   Keep user bootloaders PORTABLE (Linux / OSX / Alpine-busybox): POSIX shell + tools that
#   exist everywhere.  This one just proves it loaded at both ends of the run.
echo "user-bootloader: boot (goals=[${__argv__:-}])"
trap 'echo "user-bootloader: exit (code=${__exit_code__:-?})"' EXIT
