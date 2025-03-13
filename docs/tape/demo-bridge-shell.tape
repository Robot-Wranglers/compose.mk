#!/usr/bin/env -S PS1='\$ ' vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 17
Set Width 1000
Set Height 400
Set TypingSpeed .21
Set PlaybackSpeed 3.3
Set CursorBlink false
Type "make debian.shell"
Enter
Sleep 6s
Ctrl+D
Sleep 3 
Enter
Type "make alpine.shell"
Enter
Sleep 15s
Ctrl+D
Output img/demo-bridge-shell.gif 
