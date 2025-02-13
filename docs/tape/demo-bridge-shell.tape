#!/usr/bin/env -S PS1='\$ ' vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output docs/img/demo-bridge-shell.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 20
Set Width 1000
Set Height 400
Set TypingSpeed .21
Set PlaybackSpeed 3.3
Set CursorBlink false
Hide
Type "cd tests; cp Makefile.itest.mk Makefile"
Enter
Type 'clear' 
Enter
Show
Type "make debian/shell"
Enter
Sleep 6s
Ctrl+D
Sleep 3 
Type "make alpine/shell"
Enter
Sleep 15s
Ctrl+D
