#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/e2e-clean.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 18
Set Width 1000
Set Height 400
Set TypingSpeed .32
Set PlaybackSpeed 4
Set CursorBlink false
Type "make clean"
Enter
Sleep 15

