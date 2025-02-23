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
Type "make -f demos/etl-json.mk" etl.safe
Enter
Sleep 5s
Screenshot img/etl-json.png
#Output img/etl-json.gif 
