#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 17
Set Width 1200
Set Height 1400
Set CursorBlink false
Show 
Type "./demos/tui/extension-1.mk"
Enter
Sleep 14s
Screenshot img/tui-extension-1.png
