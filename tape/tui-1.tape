#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/tui-1.gif 
Require "make"
Require "docker"
Set Shell "bash --norc --noprofile"
Set FontSize 12
Set Width 1000
Set Height 800
Set TypingSpeed .03
Set PlaybackSpeed 1
Set CursorBlink false
Type "# Let's launch a split-screen shell context, one pane for each of the named tool containers."
Enter
Type "# The comma-delimited names below must be services that are actually defined in k8s-tools.yml."
Enter
Enter
Sleep 3
Set PlaybackSpeed 3
Type "./compose.mk loadf k8s-tools.yml tux.mux.svc/k8s,eksctl,kn,argo"
Sleep 3
Enter
Sleep 30

