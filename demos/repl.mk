#!/usr/bin/env -S make -f
#
# repl.mk: the canonical way to add a REPL to a plain Makefile without a
#   cmk-pragma.  Import the tux.repl plugin, then `__main__:
#   tux.repl/<targets>` hands the comma-separated list to the plugin's
#   `tux.repl/%` helper, which launches the Bubbletea harness wired to this
#   program's targets (the live makefile is the runner).  At launch the
#   listed targets are shown; type one (or any core target, e.g.
#   `flux.ok`) to run it; ctrl-d exits.  Needs a terminal.
#
#   USAGE:  ./demos/repl.mk          # launches the REPL over t1,t2,t3
#           ./demos/repl.mk t1       # or run a target directly (no REPL)
include compose.mk
# `require` (not plain include) so the harness's re-parsing eval child --
# which inherits the exported `__plugins__` registry -- skips re-importing
# the plugin (idempotent, child-safe).
$(call __plugins__.require, tux.repl.cmk)

t1:; @echo "t1: hello from the plain-makefile repl"
t2:; @echo "t2: the time is `date +%H:%M:%S`"
t3:; ${make} io.time.wait/1

__main__: tux.repl/t1,t2,t3
