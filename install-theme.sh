#!/bin/bash

set -euo pipefail

# Install the Quickshell Rise bar and apply the Dos-Moos Omarchy theme.
# - Quickshell Rise bar: https://github.com/HANCORE-linux/quickshell-dots
# - Dos-Moos theme:      https://github.com/HANCORE-linux/omarchy-dos-moos-theme

echo "Installing Quickshell Rise bar..."

# Quickshell Rise needs the quickshell (qs) runtime plus git/jq/curl.
# quickshell ships in the official 'extra' repo; the rest are usually present.
yay -S --noconfirm --needed quickshell git jq curl

# Run the installer non-interactively with V1 version and Claude backend
curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh | bash -s V1 --claude-backend

# Install the autostart hook so Quickshell starts on boot
HOOK_DIR="$HOME/.config/omarchy/hooks/post-boot.d"
mkdir -p "$HOOK_DIR"
curl -fsSL -o "$HOOK_DIR/quickshell-rise" \
  https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/contrib/post-boot.d/quickshell-rise
chmod +x "$HOOK_DIR/quickshell-rise"

echo "Quickshell Rise installed with autostart hook"

# Install and apply the Dos-Moos Omarchy theme (color scheme).
# This is separate from the Quickshell Rise bar above: the bar replaces waybar,
# while the Omarchy theme controls the system-wide color scheme.
THEME_URL="https://github.com/HANCORE-linux/omarchy-dos-moos-theme"
THEME_NAME="dos-moos"
THEME_DIR="$HOME/.config/omarchy/themes/$THEME_NAME"

echo "Installing Dos-Moos Omarchy theme..."

if [ ! -d "$THEME_DIR" ]; then
  # 'omarchy theme install' clones into ~/.config/omarchy/themes/<slug>
  # (here: dos-moos) and applies it automatically via omarchy-theme-set.
  omarchy theme install "$THEME_URL"
else
  # Theme already installed; just make sure it is the active theme.
  omarchy theme set "$THEME_NAME"
fi

echo "Dos-Moos theme applied"
