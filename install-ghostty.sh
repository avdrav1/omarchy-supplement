#!/bin/bash

# Install ghostty terminal emulator.
#
# Guard on the binary so a re-run on an already-provisioned machine is a true
# no-op. A bare `yay -S` pre-authenticates via sudo *before* it works out there
# is nothing to install, so without this guard the script always prompts for a
# password -- and in a non-interactive run (no tty) fails outright, showing up
# as a spurious install-all.sh failure even though ghostty is already present.
command -v ghostty &>/dev/null || yay -S --noconfirm --needed ghostty
