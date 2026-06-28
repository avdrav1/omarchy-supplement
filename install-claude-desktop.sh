#!/bin/bash

set -euo pipefail

# Install Claude Desktop (Cowork-capable frontend) on Arch via the AUR.
#
# Uses patrickjaja's actively-maintained binary package, which tracks upstream
# Claude Desktop releases and supports the Cowork feature. Pair with
# install-claude-cowork-service.sh for the native Linux Cowork backend.
# Source: https://github.com/patrickjaja/claude-desktop-bin (AUR: claude-desktop-bin)

if pacman -Qq claude-desktop-bin &>/dev/null; then
  echo "Claude Desktop (claude-desktop-bin) already installed."
  echo "Updates arrive via your AUR helper: yay -Syu"
  exit 0
fi

# Remove the older, archived aaddrick build if present. It owns
# /usr/bin/claude-desktop and would file-conflict with claude-desktop-bin.
# Plain -R keeps user data in ~/.config/Claude (no -n, no -s cascade).
# Order matters: remove the -debug split package before its parent.
for pkg in claude-desktop-debug claude-desktop; do
  if pacman -Qq "$pkg" &>/dev/null; then
    echo "Removing previous '$pkg' build (archived aaddrick PKGBUILD)..."
    sudo pacman -R --noconfirm "$pkg"
  fi
done

# Install the Cowork-capable frontend from the AUR.
yay -S --needed --noconfirm claude-desktop-bin
