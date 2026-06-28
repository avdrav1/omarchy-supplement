#!/bin/bash

set -euo pipefail

# Install or update Claude Desktop (Cowork-capable frontend) to the LATEST
# version via the AUR. Safe to re-run from install-all.sh: `yay --needed` is a
# no-op when already current and rebuilds to the latest AUR version when behind.
#
# Uses patrickjaja's actively-maintained binary package, which tracks upstream
# Claude Desktop releases and supports the Cowork feature. Pair with
# install-claude-cowork-service.sh for the native Linux Cowork backend.
# Source: https://github.com/patrickjaja/claude-desktop-bin (AUR: claude-desktop-bin)

# One-time migration: remove the older, archived aaddrick build if it is the
# literal installed package. Match against the installed list with `grep -qx`
# so we do NOT match claude-desktop-bin's `provides=claude-desktop` alias
# (matching it would uninstall the package we want). Plain -R keeps user data
# in ~/.config/Claude. Remove the -debug split package before its parent.
for pkg in claude-desktop-debug claude-desktop; do
  if pacman -Qq | grep -qx "$pkg"; then
    echo "Removing previous '$pkg' build (archived aaddrick PKGBUILD)..."
    sudo pacman -R --noconfirm "$pkg"
  fi
done

# Install if missing, or update to the latest AUR version if behind.
yay -S --needed --noconfirm claude-desktop-bin
