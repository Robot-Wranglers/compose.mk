#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 15
Set Width 1000
Set Height 350
Set TypingSpeed .21
Set PlaybackSpeed 3.3
Set CursorBlink false
Show 
Type "./demos/double-dispatch.mk"
Enter
Sleep 15s
Output img/demo.double.dispatch.gif 
