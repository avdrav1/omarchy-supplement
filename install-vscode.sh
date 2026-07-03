#!/bin/bash

set -euo pipefail

# Install Visual Studio Code (official Microsoft build) from the AUR.
# Package: visual-studio-code-bin — Microsoft's proprietary binary (Marketplace
# extensions, Settings Sync, pylance/C#), as opposed to `code` / Code - OSS in
# the extra repo. Tracked config (settings.json, keybindings.json) is stowed
# from dotfiles by install-dotfiles.sh into ~/.config/Code/User/.

if pacman -Qi visual-studio-code-bin &>/dev/null; then
  echo "Visual Studio Code already installed."
else
  yay -S --noconfirm --needed visual-studio-code-bin
fi

echo "Visual Studio Code installation complete."
