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
Type "make -f demos/tui/extension-2.mk"
Enter
Sleep 30s
Screenshot img/tui-extension-2.png
Output img/tui-extension-2.gif