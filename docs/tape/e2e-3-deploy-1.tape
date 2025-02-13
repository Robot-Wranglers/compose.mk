#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/e2e-deploy-1.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 18
Set Width 1000
Set Height 800
Set TypingSpeed .42
Set CursorBlink false
Set PlaybackSpeed 10
Type "make deploy.helm"
Enter
Enter
Sleep 28
Type "make k8s.wait"
Enter
Sleep 30
Type "# Now do it again to confirm idempotence."
Enter
Enter
Type "make deploy.helm k8s.wait"
Sleep 150
