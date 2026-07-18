#!/bin/bash

# Install hyprland-scroll-overview: a workspace overview for Hyprland driven by
# touchpad scroll (hyprpm plugin "scrolloverview", by yayuuu).
# Upstream: https://github.com/yayuuu/hyprland-scroll-overview
#
# This is an hyprpm plugin, NOT a pacman/AUR package. hyprpm compiles it against
# the Hyprland headers of the *currently installed* Hyprland, so the build is
# version-locked: after every Hyprland upgrade the plugin silently stops loading
# until `hyprpm update` rebuilds it. hypr/hyprpm-plugins.hook (installed below)
# prints a reminder after any Hyprland upgrade.
#
# Hyprland wiring (the plugin{} block, the SUPER+grave bind, the scrolloverview
# submap and the ALT+1..9 bindu lines) lives in hyprland-overrides.conf and is
# applied by install-hyprland-overrides.sh. Nothing for this plugin ships via
# the dotfiles repo -- it has no user config file outside the Hyprland config.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_REPO="https://github.com/yayuuu/hyprland-scroll-overview"
PLUGIN_NAME="scrolloverview"

if ! command -v hyprpm >/dev/null 2>&1; then
  echo "hyprpm not found (ships with Hyprland). Install Hyprland first."
  exit 1
fi

# hyprpm needs the toolchain to compile the plugin against Hyprland's headers.
sudo pacman -S --noconfirm --needed base-devel cmake meson ninja cpio git

# NOTE: hyprpm elevates itself via sudo to write its state under
# /var/cache/hyprpm/$USER (root-owned), so the calls below may prompt for a
# password. That is also why this step cannot be automated from a pacman hook.

# `hyprpm add` is not re-runnable -- it errors if the repo is already present --
# so guard on the plugin already being known to hyprpm.
if hyprpm list 2>/dev/null | grep -q "$PLUGIN_NAME"; then
  echo "Plugin $PLUGIN_NAME already added; updating."
  hyprpm update
else
  hyprpm add "$PLUGIN_REPO"
fi

hyprpm enable "$PLUGIN_NAME"

# Load the plugin into the running compositor. Without this the dispatchers
# (scrolloverview:overview etc.) don't exist yet and `hyprctl configerrors`
# reports "Invalid dispatcher" for every bind until the next login.
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  hyprpm reload -n
fi

# Post-upgrade reminder hook, mirroring quickshell/quickshell-check.hook.
# It only notifies: the rebuild needs an interactive sudo, which a pacman hook
# has no tty for.
echo "Installing pacman hook for post-upgrade plugin checks..."
sudo mkdir -p /etc/pacman.d/hooks
sudo cp "$SCRIPT_DIR/hypr/hyprpm-plugins.hook" /etc/pacman.d/hooks/hyprpm-plugins.hook

echo "hyprland-scroll-overview installation complete."
echo "Toggle the overview with SUPER+\` (grave)."
