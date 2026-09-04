#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
#
# Records the stack-of-stacks demo in its TUI view: the tux.repl over
# demos/cmk/stack-of-stacks.cmk with the `fork.minimap` feeder driving the right-hand
# tree-minimap.  On REPL entry the file's __main__ auto-runs (fork = one control-stack per
# branch, joined), and `fork.minimap` reads the per-branch K files so the fork FOREST renders
# as sibling stacks under a `fork` root -- each branch shows a live running/done status and its
# active frame.  FORK_DELAY paces the per-frame pushes so the minimap animates as branches build.
#
# USAGE (from the repo root, like the sibling tui-*.tape / repl-debugger.tape scripts):
#   vhs docs/tape/stack-of-stacks.tape
Output img/stack-of-stacks.gif
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 12
Set Width 1000
Set Height 900
Set TypingSpeed .03
Set PlaybackSpeed 1
Set CursorBlink false

Type "# stack-of-stacks in the REPL: fork runs one control-stack per branch, joined."
Enter
Type "# The right-hand tree-minimap (fork.minimap) shows the forest -- one stack per branch."
Enter
Enter
Sleep 3

# Launch the REPL over the demo.  VM_TRACE + CMK_REPL_MINIMAP=fork.minimap wire the forest
# feeder to the minimap region; FORK_DELAY paces the frame pushes so the tree animates.  Needs a
# tty (vhs provides one) and docker for the embedded TUI.
Type "FORK_DELAY=1 CMK_PRAGMA_VM_TRACE=1 CMK_REPL_MINIMAP=fork.minimap ./compose.mk cmk repl demos/cmk/stack-of-stacks.cmk"
Enter

# Bootstrap: the embedded-TUI container comes up + the REPL initializes (cold-ish).
Sleep 20s

# __main__ auto-runs on entry: two forks of three branches (independent, then seeded).  The
# minimap animates each branch's stack growing, then settles on the joined forest.
Sleep 12s

# Re-run one fork by hand to show the forest animate live from the prompt.
Type "fork/handler/a,handler/b,handler/c"
Enter
Sleep 10s

# Quit the REPL (the Go wrapper's `^D quit`).
Ctrl+D
Sleep 2s
