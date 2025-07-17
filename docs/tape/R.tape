#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 13
Set Width 800
Set Height 600
Show 
Type "./demos/r.mk"
Enter
Sleep 13s
Screenshot img/R.png
