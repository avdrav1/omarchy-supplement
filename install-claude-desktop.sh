#!/bin/bash

set -euo pipefail

# Install or update Claude Desktop to the LATEST version via the AUR. Safe to
# re-run from install-all.sh: `yay --needed` is a no-op when already current and
# rebuilds to the latest AUR version when behind.
#
# Uses Anthropic's OFFICIAL Linux build (AUR: claude-desktop), which ships Chat,
# Cowork, and Claude Code. This supersedes the third-party stacks we used
# before -- patrickjaja's claude-desktop-bin (removed from the AUR) plus the
# separate claude-cowork-service backend (now deprecated: the official build
# has native Cowork, so install-claude-cowork-service.sh is no longer needed).
# Source: AUR: claude-desktop

# One-time migration: remove superseded third-party builds if installed. Plain
# -R keeps user data in ~/.config/Claude. `claude-desktop-bin` was patrickjaja's
# binary package (its `provides=claude-desktop` alias means yay -S alone won't
# swap it out for the real claude-desktop). `claude-desktop-debug` was the older
# aaddrick split package; remove it before any parent.
for pkg in claude-desktop-debug claude-desktop-bin; do
  if pacman -Qq | grep -qx "$pkg"; then
    echo "Removing superseded '$pkg' build..."
    sudo pacman -R --noconfirm "$pkg"
  fi
done

# Install if missing, or update to the latest AUR version if behind.
yay -S --needed --noconfirm claude-desktop
