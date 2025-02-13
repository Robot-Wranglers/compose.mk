#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/demo-io.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 14
Set Width 1000
Set Height 550
Set TypingSpeed .21
Set PlaybackSpeed 3.3
Set CursorBlink false
Type "make -f demo/etl-img.mk etl"
Enter
Sleep 54s
