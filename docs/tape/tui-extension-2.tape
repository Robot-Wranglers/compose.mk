#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 17
Set Width 1600
Set Height 1250
Set CursorBlink false
Set PlaybackSpeed .9
Show 
Type "./demos/tui/extension-2.mk"
Enter
Sleep 40s
Screenshot img/tui-extension-2.png
Output img/tui-extension-2.gif