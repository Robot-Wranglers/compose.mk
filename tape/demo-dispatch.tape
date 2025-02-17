#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/demo-dispatch.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 18
Set Width 1000
Set Height 300
Set TypingSpeed .21
Set PlaybackSpeed 3.3
Set CursorBlink false
Hide
Type "cd tests; cp Makefile.itest.mk Makefile"
Enter
Type 'clear' Enter
Show 
Type "make demo"
Enter
Sleep 15s
