#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
#
# Records the tux.repl.debugger: a live VM call-stack debugger built on tux.repl.
# The driver `demos/cmk/debugger-example.cmk` runs a deep, mixed-flow-control debuggee
# (`demo.build`: a goto-looped build pipeline with ${make} nesting + flux fan-out) whose
# real frame stack is rendered by `tux.repl.debugger.feed` into four regions -- a modeline
# (instruction pointer ${@} + clock), a LAST-COMMAND buffer, a live CALL-STACK tree, and an
# ENV buffer.  The goto loop re-dispatches each step (CMK_FRAME_WAIT=1s), so the tree
# animates on its own -- no input needed until we quit.
#
# USAGE (from the repo root, like the sibling tui-*.tape scripts):
#   vhs docs/tape/repl-debugger.tape
Output img/repl-debugger.gif
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 12
Set Width 1000
Set Height 900
Set TypingSpeed .03
Set PlaybackSpeed 1
Set CursorBlink false

Type "# tux.repl.debugger: a live VM call-stack debugger (tux.repl + __vm__.frames)."
Enter
Type "# The debuggee is a goto-looped build pipeline; watch the call-stack tree animate."
Enter
Enter
Sleep 3

# Launch the debugger front-end (needs a tty -- vhs provides one -- and docker for the TUI).
Type "./demos/cmk/debugger-example.cmk"
Enter

# Bootstrap: the embedded-TUI container comes up + the REPL frames initialize (cold-ish).
Sleep 20s

# Let the demo.build goto-loop run: the LAST-COMMAND / CALL-STACK-tree / ENV regions
# update once per step (CMK_FRAME_WAIT=1s), so this captures ~25 frames of live stepping.
Sleep 25s

# Quit the REPL (the Go wrapper's `^D quit`).
Ctrl+D
Sleep 2s
