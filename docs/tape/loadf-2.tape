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
Type "layout=horizontal ./compose.mk loadf tests/docker-compose.yml tux.open.service_shells/debian,alpine,ubuntu"
Enter
Sleep 15s
Screenshot img/loadf-2.png
Output img/loadf-2.gif 
