#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/tui-2.gif 
Require "make"
Require "docker"
Set Shell "bash --norc --noprofile"
Set FontSize 16
Set Width 1300
Set Height 800
Set TypingSpeed .025
Set PlaybackSpeed 1
Set CursorBlink false
Type "# Let's launch a split-screen shell context for each of the named make-targets."
Enter
Sleep 1.0
Type "# This combines several instances of the 'io.wait/<seconds>' target "
Enter
Type "# into separate tmux panels.  Each exits, leaving only the default shell."
Enter 2
Sleep 2
Set PlaybackSpeed 2
Type "./compose.mk tux.mux/io.bash,io.wait/5,io.wait/7,io.wait/9,io.wait/11"
Sleep 3.3
Enter
Sleep 10

