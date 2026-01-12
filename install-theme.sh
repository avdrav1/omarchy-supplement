#!/bin/bash

set -euo pipefail

# Install Omarchy themes
omarchy-theme-install https://github.com/OldJobobo/omarchy-miasma-theme

# Sync Miasma waybar-theme config + style into waybar dotfiles and live config
MIASMA_WAYBAR_THEME_DIR="$HOME/.config/omarchy/themes/miasma/waybar-theme"

if [ -d "$MIASMA_WAYBAR_THEME_DIR" ]; then
  DOTFILES_WAYBAR_DIR="$HOME/dotfiles/waybar/.config/waybar"
  LIVE_WAYBAR_DIR="$HOME/.config/waybar"

  mkdir -p "$DOTFILES_WAYBAR_DIR" "$LIVE_WAYBAR_DIR"

  # Copy config.jsonc and style.css from the Miasma waybar-theme
  for f in config.jsonc style.css; do
    if [ -f "$MIASMA_WAYBAR_THEME_DIR/$f" ]; then
      cp "$MIASMA_WAYBAR_THEME_DIR/$f" "$DOTFILES_WAYBAR_DIR/$f"
      cp "$MIASMA_WAYBAR_THEME_DIR/$f" "$LIVE_WAYBAR_DIR/$f"
    fi
  done
fi

omarchy-restart-waybar
