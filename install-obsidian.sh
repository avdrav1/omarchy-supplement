#!/bin/bash

set -euo pipefail

# Install Obsidian (Markdown knowledge base) from the official Arch extra repo.
#
# Note: Obsidian's real settings live per-vault in a `.obsidian/` folder inside
# each vault, not in ~/.config — so there is no global config to track in
# dotfiles. Carry per-vault config with the vault itself (e.g. via Syncthing).
# ~/.config/obsidian holds only Electron cache/window state.

if pacman -Qi obsidian &>/dev/null; then
  echo "Obsidian already installed."
else
  sudo pacman -S --noconfirm --needed obsidian
fi

echo "Obsidian installation complete."
