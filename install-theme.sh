#!/bin/bash

set -euo pipefail

# Install Quickshell Rise bar theme
# https://github.com/HANCORE-linux/quickshell-dots

echo "Installing Quickshell Rise bar..."

# Run the installer non-interactively with V1 version and Claude backend
curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh | bash -s V1 --claude-backend

# Install the autostart hook so Quickshell starts on boot
HOOK_DIR="$HOME/.config/omarchy/hooks/post-boot.d"
mkdir -p "$HOOK_DIR"
curl -fsSL -o "$HOOK_DIR/quickshell-rise" \
  https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/contrib/post-boot.d/quickshell-rise
chmod +x "$HOOK_DIR/quickshell-rise"

echo "Quickshell Rise installed with autostart hook"
