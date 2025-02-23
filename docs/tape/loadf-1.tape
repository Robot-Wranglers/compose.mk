#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
#Output img/demo.double.dispatch.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 10
Set Width 1200
Set Height 768
Show 
Type "./compose.mk loadf demos/data/docker-compose.yml"
Enter
Sleep 8s
Screenshot img/loadf-1.png
Sleep 8s
Output img/loadf-1.gif 
