#!/bin/bash

# Install ghostty terminal emulator
yay -S --noconfirm --needed ghostty

# Install Catppuccin Mocha theme for Ghostty
THEMES_DIR="$HOME/.config/ghostty/themes"
mkdir -p "$THEMES_DIR"

# Download the Catppuccin Mocha theme if it does not already exist
if [ ! -f "$THEMES_DIR/catppuccin-mocha" ]; then
  curl -fsSL \
    https://raw.githubusercontent.com/catppuccin/ghostty/main/themes/catppuccin-mocha \
    -o "$THEMES_DIR/catppuccin-mocha"
fi
