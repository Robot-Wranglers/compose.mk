#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/e2e-deploy-2.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 18
Set Width 1000
Set Height 950
Set TypingSpeed 1.0
Set PlaybackSpeed 10
Set CursorBlink false
Type "make deploy.test_harness"
Enter
Sleep 340

