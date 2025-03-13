#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/tui-3.gif 
Require "make"
Require "docker"
Set Shell "bash --norc --noprofile"
Set FontSize 16
Set Width 1200
Set Height 800
Set TypingSpeed .055
Set PlaybackSpeed 2
Set CursorBlink false
Type "# The 'loadf' target can open shells for each service in a given compose file."
Enter
Enter
Sleep 3.3
Set PlaybackSpeed 3
Type "./compose.mk loadf demos/data/docker-compose.yml"
Sleep 2.8
Enter
Sleep 30

