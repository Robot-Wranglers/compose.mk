#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
Set Shell "bash --norc --noprofile"
Set FontSize 16
Set Width 1200
Set Height 800
Set TypingSpeed .055
# Set PlaybackSpeed 2
Set CursorBlink false
#Type "# Scoordinating usage of `tmux` and `tte`"
#Enter
#Enter
#Sleep 3.3
Set PlaybackSpeed 1
Type "./compose.mk tux.demo"
Sleep 1
Enter
Sleep 45
Output img/tui-tte.gif 
