#!/bin/bash
# The Rebirth theme (config/themes/rebirth), made active on first install
source "$(dirname "$0")/../lib/common.sh"

# Rebirth was generated locally with Aether and has no upstream repo. It is
# copied, not linked, because Aether rewrites a theme directory in place; to
# carry a change back, copy ~/.config/omarchy/themes/rebirth over
# config/themes/rebirth and commit.
step "Rebirth theme"
THEME_DIR="$HOME/.config/omarchy/themes/rebirth"
if [ ! -d "$THEME_DIR" ]; then
  mkdir -p "$(dirname "$THEME_DIR")"
  cp -r "$CONFIG/themes/rebirth" "$THEME_DIR"
  # Only on first install, so a re-run never overrides a theme picked since.
  omarchy theme set rebirth
fi
