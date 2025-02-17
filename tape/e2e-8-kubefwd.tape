#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/e2e-kubefwd.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 16
Set Width 1100
Set Height 800
Set TypingSpeed .03
Set PlaybackSpeed 1
Set CursorBlink false
Type "# Let's use kubefwd with the current kube-context,"
Enter
Type "# forwarding the 'default' namespace to the host."
Enter
Enter
Type "make kubefwd.start/default"
Enter
Sleep 13
Enter
Type "# Now cluster internals are accessible from your host, including DNS."
Enter
Enter
Type "curl http://nginx-service:12000"
Enter
Sleep 8
