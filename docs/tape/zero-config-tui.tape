#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 10
Set Width 1200
Set Height 768
Show 
Type "layout=horizontal ./compose.mk \"
Enter 
Type "  mk.include/demos/no-include.mk \"
Enter
Type "  tux.open/flux.loopf/test,flux.wrap/clean:build"
Enter
Sleep 8s
Screenshot img/zero-config-tui.png
Sleep 25s
Output img/zero-config-tui.gif 
