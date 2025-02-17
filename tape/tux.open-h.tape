#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
#Output img/demo.double.dispatch.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 10
Set Width 1000
Set Height 768
Show 
Type "./compose.mk tux.open.horizontal/flux.ok,flux.ok,flux.ok"
Enter
Sleep 8s
Screenshot img/tux.open-h.png