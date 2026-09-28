#!/bin/bash

set -euo pipefail

# Apply the Solitude Omarchy theme -- what the reference machine (alienware)
# runs. Dos-Moos, the theme this script used to set, is by the same author and
# stays installed wherever it already is; it is just no longer the active one.
# - Solitude theme: https://github.com/HANCORE-linux/omarchy-solitude-theme
#
# The bar is no longer installed here. This script used to also install the
# Quickshell Rise bar; that has been superseded by Shibumi Shell, which
# install-shibumi.sh installs (and which retires the leftover Rise footprint).

# ── Solitude Omarchy theme ───────────────────────────────────────────────────
THEME_URL="https://github.com/HANCORE-linux/omarchy-solitude-theme"
THEME_NAME="solitude"
THEME_DIR="$HOME/.config/omarchy/themes/$THEME_NAME"

echo "Installing Solitude Omarchy theme..."

if [ ! -d "$THEME_DIR" ]; then
  # 'omarchy theme install' clones into ~/.config/omarchy/themes/<slug>
  # (here: solitude) and applies it automatically via omarchy-theme-set.
  omarchy theme install "$THEME_URL"
else
  # Theme already installed; just make sure it is the active theme.
  omarchy theme set "$THEME_NAME"
fi

echo "Solitude theme applied"
