#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/e2e-interactive-shell.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 18
Set Width 1000
Set Height 350
Set TypingSpeed .25
Set PlaybackSpeed 5
Set CursorBlink false
Type "make cluster.shell"
Enter
Sleep 30 
Ctrl+D

