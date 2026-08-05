#!/bin/bash

set -euo pipefail

# Apply the Dos-Moos Omarchy theme and install the Quickshell Rise bar.
# - Dos-Moos theme:      https://github.com/HANCORE-linux/omarchy-dos-moos-theme
# - Quickshell Rise bar: https://github.com/HANCORE-linux/quickshell-dots

# ── Dos-Moos Omarchy theme ───────────────────────────────────────────────────
# Deliberately FIRST. The theme is the system-wide color scheme and has no
# dependency on the Quickshell Rise bar below. When the bar ran first, any
# failure there tripped `set -e` and skipped theming entirely -- and since
# install-all.sh has no `set -e`, the run still printed its "Manual steps"
# summary and looked successful.
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
  snappy-switcher quit >/dev/null 2>&1 || true
  pkill -f 'snappy-switcher --daemon' >/dev/null 2>&1 || true
  sleep 1
  hyprctl dispatch exec 'snappy-switcher --daemon' >/dev/null 2>&1 || true
fi

# ── Quickshell Rise bar ──────────────────────────────────────────────────────
# Runs on Omarchy 3 (replacing waybar) and Omarchy 4 / quattro alike. Upstream
# now detects quattro itself (qsr_has_quattro) and, with --autostart, hides the
# stock omarchy bar rather than fighting it.
#
# No quickshell package work happens here any more. Upstream's dependency check
# only wants `qs` on PATH, so Rise runs against whatever quickshell the machine
# already has -- including the quickshell-git that omarchy 4's own shell depends
# on. We used to force-remove that and build a pinned mainstream-quickshell-git
# from quickshell/PKGBUILD, which conflicted with omarchy-bar and made the whole
# bar Omarchy-3-only; verified unnecessary on omarchy 4 (2026-08-05).
echo "Installing Quickshell Rise bar..."

# Install what upstream would otherwise install mid-run. Its font step shells
# out to `sudo pacman` from inside a `set -e` script, so a machine without the
# fonts aborts the whole install at that point on a sudo prompt. Doing it here
# keeps every privileged action in one predictable place. bluez-utils provides
# `bluetoothctl`, which the bar's Bluetooth widget shells out to for power state
# and connected-device count; pacman-contrib provides `checkupdates`, which the
# updater panel requires.
sudo pacman -S --noconfirm --needed \
  git jq curl pacman-contrib bluez-utils \
  ttf-jetbrains-mono-nerd ttf-material-symbols-variable

# --autostart installs the post-boot hook AND, on quattro, hides the stock bar
# (a state Rise tracks as its own, so --no-autostart hands it back). The bar
# itself is started and health-checked by the installer regardless of this flag.
curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh \
  | bash -s V1 --claude-backend --autostart

echo "Quickshell Rise installed with autostart hook"
