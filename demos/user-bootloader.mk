#!/usr/bin/env -S make -f
# demos/user-bootloader.mk: an @file:goal takeover bootloader.

# CMK_BOOTLOADER=@<file>:<goal> execs make -f file goal -- a TARGET

# that takes over the run (vs the sourced <file> form in the .sh).

# The supervisor forwards __argv__ (the goals) and CMK_TRAMP_MK (the

# make command) so an alternate backend can drive the program itself.

# USAGE (see also user-bootloader.sh + test_bootloader.py):

# CMK_BOOTLOADER=@demos/user-bootloader.mk:user.tramp cmk flux.ok

user.tramp:
	@echo "user-tramp: took over (goals=[$(__argv__)] make=[$(CMK_TRAMP_MK)])"
