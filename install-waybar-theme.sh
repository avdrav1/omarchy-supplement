#!/bin/bash

set -euo pipefail

# Install Waybar-related modules
yay -S --noconfirm --needed waybar-module-pacman-updates-git
yay -S --noconfirm --needed wttrbar

# Install HANCORE Waybar V6.fa theme
TMP_REPO="/tmp/repo"
rm -rf "$TMP_REPO"
git clone https://github.com/HANCORE-linux/waybar-themes.git "$TMP_REPO"
cp -rf "$TMP_REPO/config/V6.fa/." "$HOME/.config/waybar"
rm -rf "$TMP_REPO"

# Restart Waybar via Omarchy helper
omarchy-restart-waybar
