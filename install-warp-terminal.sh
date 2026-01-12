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
  sudo sh -c "echo -e '\n[warpdotdev]\nServer = https://releases.warp.dev/linux/pacman/$repo/$arch' >> /etc/pacman.conf"
fi

# Import and sign Warp repository key (ignore failure if already present)
sudo pacman-key -r "[email protected]" || true
sudo pacman-key --lsign-key "[email protected]" || true

# Install warp-terminal via pacman
sudo pacman -Sy --noconfirm --needed warp-terminal
