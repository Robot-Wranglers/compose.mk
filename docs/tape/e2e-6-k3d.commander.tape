#!/usr/bin/env -S PS1="\$ " vhs
# This file describes terminal videos with the `vhs` tool (https://github.com/charmbracelet/vhs)
Output img/e2e-k3d.commander.gif 
Require "make"
Require "docker"
Set Shell "bash"
Set FontSize 12
Set Width 1600
Set Height 1000
Set TypingSpeed .03
Set PlaybackSpeed 1.2
Set CursorBlink false
Type "# Demonstrating custom TUIs.  "
Enter
Type "# The 'k3d.commander' target launches a 5-pane layout.  "
Enter
Type "# A large primary pane dispatches any named targets, in this case running the 'cluster', 'deploy', and 'test' targets from the E2E test.  "
Enter
Type "# Additional panes are launched for k9s, lazydocker, and a k3d-container shell. "
Enter
Enter
Type "# For more info, see the API docs for 'k3d.commander'."
Enter
Enter
Type "KUBECONFIG=./fake.profile.yaml ./k8s.mk k3d.commander/cluster.wait,cluster.test"
Sleep 4.5
Enter
Sleep 220