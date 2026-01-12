#!/bin/bash

set -euo pipefail

# Install Claude Desktop on Arch using unofficial PKGBUILD
# Source: https://github.com/aaddrick/claude-desktop-arch

if pacman -Qs claude-desktop &>/dev/null; then
  echo "Claude Desktop package already installed."
  exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cd "$TMP_DIR"
git clone https://github.com/aaddrick/claude-desktop-arch.git
cd claude-desktop-arch

# Build and install the package (will prompt for sudo via pacman as needed)
makepkg -si --noconfirm
