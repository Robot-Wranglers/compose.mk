#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/demo.double.dispatch.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 17
Set Width 1000
Set Height 450
Set PlaybackSpeed 3.3
Set TypingSpeed .32
Set CursorBlink false
Hide
Type "cd tests; cp Makefile.itest.mk Makefile"
Enter
Type 'clear' Enter
Show 
Type "make demo.double.dispatch"
Enter
Sleep 22s
