#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 17
Set Width 1100
Set Height 400
Set TypingSpeed .35
Set PlaybackSpeed 3.3
Set CursorBlink false
Type "echo uname -n -v | make debian.shell.pipe"
Enter
Sleep 6s
Enter
Sleep 3 
Type "echo echo echo hello-world | make alpine.pipe | make debian.pipe"
Enter
Sleep 6s
Output img/demo-bridge-stream.gif 
