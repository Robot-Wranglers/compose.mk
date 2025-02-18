#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 14
Set Width 1000
Set Height 550
Set TypingSpeed .21
Set PlaybackSpeed 3.3
Set CursorBlink false
Type "./compose.mk help io.print.div"
Enter
Sleep 4s
Enter
Enter
Type "# Using `io.print.div` with no argument shows a time-stamped screen divider"
Sleep 1s
Enter
Enter
Type "./compose.mk io.print.div"
Enter
Sleep 2s
Enter
Type "# If an argument is provided, it is used to determine the width of the divider"
Enter
Enter
Type "./compose.mk io.print.div/2"
Enter
Enter
Type "# You can also override the default timestamp with an explicit label"
Enter
Enter
Sleep 2s
Type "label=MyStageName ./compose.mk io.print.div"
Enter
Sleep 5s
Output img/demo-io.gif 
