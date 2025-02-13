#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/demo-gum.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 14
Set Width 1000
Set Height 550
Set TypingSpeed .21
Set PlaybackSpeed 3.3
Set CursorBlink false
Type "./compose.mk help io.gum.div"
Enter
Sleep 4.5s
Enter
Enter
Type "# Using `io.gum.div` with no argument shows a time-stamped screen divider"
Sleep 1s
Enter
Enter
Type "./compose.mk io.gum.div"
Enter
Sleep 2s
Enter
Enter
Type "# You can also override the default timestamp with an explicit label"
Enter
Enter
Sleep 2s
Type "label=MyStageName ./compose.mk io.gum.div"
Enter
Sleep 5s
