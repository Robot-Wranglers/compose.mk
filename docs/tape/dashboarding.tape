#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 10
Set Width 1200
Set Height 1000
Show 
# Set TypingSpeed 1.33
Type "make -f demos/dashboarding.mk demo.ui"
Enter
Sleep 15s
Screenshot img/dashboarding.png
Set PlaybackSpeed .5
Sleep 10s
Output img/dashboarding.gif 
