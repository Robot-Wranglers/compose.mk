#!/usr/bin/env -S PS1='\$ ' vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 20
Set Width 1000
Set Height 400
Set CursorBlink false
Hide
Type "./compose.mk mk.select/demos/no-include.mk"
Enter
Sleep 10s
Ctrl+D
Screenshot img/mk.select.png
Output img/mk.select.gif 
