#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/tui-5.gif 
Require "make"
Require "docker"
Set Shell "bash --norc --noprofile"
Set FontSize 15
Set Width 1200
Set Height 900
Set TypingSpeed .035
Set PlaybackSpeed 1
Set CursorBlink false
Type "# Demonstrating custom TUIs.  "
Enter
Type "# This launches a dockerized command/control interface for docker, using docker-in-docker."
Enter
Type "# You can read more in the API docs for 'docker.commander'."
Enter
Enter
Sleep 1.3
Type "./compose.mk docker.commander"
Enter
Sleep 22
