#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/gui3.gif
Require "make"
Require "docker"
Set PlaybackSpeed .8
Set Shell "bash"
Set FontSize 10
Set Width 1000
Set Height 800
Set TypingSpeed .03
Set PlaybackSpeed 1
Set CursorBlink false
Type "./demos/cmk/xpra-net.cmk gui"
Sleep .5
Enter
Sleep 60