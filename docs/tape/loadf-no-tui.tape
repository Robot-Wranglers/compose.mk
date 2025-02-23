#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
Set Shell "bash --norc --noprofile"
Set FontSize 15
Set Width 1200
Set Height 300
Set TypingSpeed .03
Set PlaybackSpeed 2
Set CursorBlink false
# Type "# The 'loadf' command takes a compose file, runs 'compose.import' for it,"
# Enter
# Type "# then runs any additional commands that are given inside of the resulting context."
# Enter
# Enter
# Sleep 3.3
# Set PlaybackSpeed 9
Type "./compose.mk loadf demos/data/docker-compose.yml alpine.get_shell debian.get_shell ubuntu.get_shell"
Enter
Sleep 8
Screenshot img/loadf-no-tui.png
# Sleep 24
# Output img/loadf-no-tui.gif 
