#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
#Output img/demo.double.dispatch.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 10
Set Width 1600
Set Height 1000
Show 
Type "./compose.mk tux.open.vertical/flux.ok,flux.ok"
Enter
Sleep 8s
Screenshot img/tux.open-v.png