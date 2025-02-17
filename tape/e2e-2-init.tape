#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/e2e-init.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 18
Set Width 1000
Set Height 500
Set TypingSpeed .55
Set PlaybackSpeed 8
Set CursorBlink false
Type "make cluster"
Enter
Sleep 76

