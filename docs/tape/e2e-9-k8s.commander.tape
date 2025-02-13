#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/e2e-k8s.commander.gif 
Require "make"
Require "docker"
Set Shell "bash --norc --noprofile"
Set FontSize 15
Set Width 1200
Set Height 900
Set TypingSpeed .028
Set PlaybackSpeed 1
Set CursorBlink false
Type "# Demonstrating custom TUIs.  "
Enter
Type "# This launches a dockerized command/control interface for k8s, and dispatches commands to it."
Enter
Type "# The invocation below runs the 'cluster', 'deploy', & 'test' targets as before, showing extra context."
Enter
Type "# Note the kube-context and namespace details on the status bar, and the namespace topology preview"
Enter
Type "# on the right side. You can read more in the API docs for 'k8s.commander'."
Enter
Enter
Sleep 1.3
Type "make k8s.commander/cluster,deploy,test"
Enter
Sleep 90
