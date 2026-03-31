#!/bin/bash

set -euo pipefail

# Install Warp Terminal on Arch via official pacman repository
if command -v warp-terminal &>/dev/null; then
  echo "Warp Terminal already installed."
  exit 0
fi

# Ensure warpdotdev repo exists in pacman.conf
if ! grep -q "^\[warpdotdev\]" /etc/pacman.conf; then
  echo "Adding Warp pacman repository to /etc/pacman.conf..."
  sudo sh -c 'printf "\n[warpdotdev]\nServer = https://releases.warp.dev/linux/pacman/\$repo/\$arch\n" >> /etc/pacman.conf'
fi

# Import and locally sign Warp's package-signing key
sudo pacman-key -r 19A1E427461B1795F73F629631F4254AFE49E02E
sudo pacman-key --lsign-key 19A1E427461B1795F73F629631F4254AFE49E02E

# Install warp-terminal via pacman
sudo pacman -Sy --noconfirm --needed warp-terminal
