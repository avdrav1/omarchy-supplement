#!/bin/bash

set -euo pipefail

# Install Slack Desktop from the AUR (package: slack-desktop).
#
# Note: Slack stores an Electron profile with per-machine secrets/workspace
# state in ~/.config/Slack; it is intentionally NOT tracked in dotfiles.
# Sign in per machine on first launch.

if pacman -Qi slack-desktop &>/dev/null; then
  echo "Slack already installed."
else
  yay -S --noconfirm --needed slack-desktop
fi

echo "Slack installation complete."
