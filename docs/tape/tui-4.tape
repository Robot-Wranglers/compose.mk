#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/tui-4.gif 
Require "make"
Require "docker"
Set Shell "bash --norc --noprofile"
Set FontSize 15
Set Width 1200
Set Height 600
Set TypingSpeed .03
Set PlaybackSpeed 2
Set CursorBlink false
Type "# The 'loadf' command takes a compose file, runs 'compose.import' for it,"
Enter
Type "# then runs any additional commands that are given inside of the resulting context."
Enter
Type "# The effect is similar to project-integration, but more automatic, requiring no project makefile."
Enter
Enter
Sleep 3.3
Set PlaybackSpeed 9
Type "./compose.mk loadf tests/docker-compose.yml alpine/get_shell debian/get_shell ubuntu/get_shell"
Enter
Sleep 24

