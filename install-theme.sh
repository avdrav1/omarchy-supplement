#!/bin/bash

set -euo pipefail

# Apply the Rebirth Omarchy theme -- what the reference machine (alienware)
# runs. Solitude and Dos-Moos, the themes this script used to set, stay
# installed wherever they already are; they are just no longer the active one.
#
# Rebirth was generated locally with Aether and has no upstream repo, so its
# source is tracked in themes/rebirth. It is copied rather than symlinked, and
# only when absent: Aether rewrites a theme directory in place, which through a
# symlink would land in this repo, and a re-run must not discard that work. To
# carry a change back, copy the directory into themes/rebirth and commit.
#
# The bar is no longer installed here. This script used to also install the
# Quickshell Rise bar; that has been superseded by Shibumi Shell, which
# install-shibumi.sh installs (and which retires the leftover Rise footprint).

# ── Rebirth Omarchy theme ────────────────────────────────────────────────────
THEME_NAME="rebirth"
THEME_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/themes/$THEME_NAME"
THEME_DIR="$HOME/.config/omarchy/themes/$THEME_NAME"

echo "Installing Rebirth Omarchy theme..."

if [ ! -d "$THEME_DIR" ]; then
  mkdir -p "$(dirname "$THEME_DIR")"
  cp -r "$THEME_SOURCE" "$THEME_DIR"
fi

omarchy theme set "$THEME_NAME"

echo "Rebirth theme applied"
