#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
#Set Shell "bash --norc --noprofile"
Set FontSize 16
Set Width 1200
Set Height 800
Set TypingSpeed .055
Set PlaybackSpeed 1.7
Set CursorBlink false
Type "# Help with no arguments lists all targets"
Enter
Enter
Sleep 1.8
Type "./compose.mk help"
Sleep 3
Enter
Sleep 6
Enter
Type "# You can also show help for a specific target: "
Enter
Enter
Sleep 3.5
Type "./compose.mk help docker.image.run"
Sleep 4.2
Enter
Sleep 18
Enter
Enter
Type "# Or show help for an entire namespace: "
Enter
Enter
Type "./compose.mk help docker"
Sleep 4.5
Enter
Sleep 45
Output img/cli-help.gif 
