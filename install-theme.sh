#!/bin/bash

set -euo pipefail

# Apply the Dos-Moos Omarchy theme.
# - Dos-Moos theme: https://github.com/HANCORE-linux/omarchy-dos-moos-theme
#
# The bar is no longer installed here. This script used to also install the
# Quickshell Rise bar; that has been superseded by Shibumi Shell, which
# install-shibumi.sh installs (and which retires the leftover Rise footprint).

# ── Dos-Moos Omarchy theme ───────────────────────────────────────────────────
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

# snappy-switcher only reads its config.ini at daemon startup, so a running
# instance won't pick up the themed (Dos-Moos) config that ships via the dotfiles
# stow. Restart it here -- after the theme is applied -- so the switcher matches
# the rest of the desktop. Guarded on an active Hyprland session and the binary
# being installed, and kept non-fatal so theming never breaks here.
if command -v snappy-switcher >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  echo "Restarting snappy-switcher to apply its themed config..."
  # Where the systemd user unit owns the daemon, restart through it -- tearing
  # it down by hand and starting a raw replacement leaves systemd believing the
  # service is dead while an unsupervised daemon holds the socket.
  if systemctl --user is-enabled snappy-switcher.service >/dev/null 2>&1; then
    systemctl --user restart snappy-switcher.service >/dev/null 2>&1 || true
  else
    snappy-switcher quit >/dev/null 2>&1 || true
    pkill -x snappy-switcher >/dev/null 2>&1 || true
    sleep 1
    # Same Lua-vs-hyprlang split as install-snappy-switcher.sh: `hyprctl dispatch
    # exec <cmd>` is a parse error under the Lua parser, so the restart here would
    # kill the daemon and never bring it back.
    if [ -f "$HOME/.config/hypr/hyprland.lua" ]; then
      hyprctl dispatch 'hl.dsp.exec_cmd("snappy-switcher --daemon")' >/dev/null 2>&1 || true
    else
      hyprctl dispatch exec 'snappy-switcher --daemon' >/dev/null 2>&1 || true
    fi
  fi
fi
