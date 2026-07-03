#!/bin/bash

set -euo pipefail

# Install the Quickshell Rise bar and apply the Dos-Moos Omarchy theme.
# - Quickshell Rise bar: https://github.com/HANCORE-linux/quickshell-dots
# - Dos-Moos theme:      https://github.com/HANCORE-linux/omarchy-dos-moos-theme

echo "Installing Quickshell Rise bar..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FALLBACK_MIRROR="Server = https://mirror.rackspace.com/archlinux/\$repo/os/\$arch"
MIRRORLIST=/etc/pacman.d/mirrorlist

# The omarchy stable mirror may lag behind on newer Qt6 package revisions.
# Add a fallback mirror so pacman can find anything the primary mirror is missing,
# then remove it afterwards so the system stays on the stable mirror.
add_fallback_mirror() {
  if ! grep -qF 'mirror.rackspace.com' "$MIRRORLIST"; then
    echo "$FALLBACK_MIRROR" | sudo tee -a "$MIRRORLIST" > /dev/null
  fi
}

remove_fallback_mirror() {
  sudo sed -i '/mirror.rackspace.com/d' "$MIRRORLIST"
}

# bluez-utils provides `bluetoothctl`, which the Quickshell Rise bar's Bluetooth
# widget shells out to for power state and connected-device count.
add_fallback_mirror
sudo pacman -Sy --noconfirm --needed \
  git jq curl bluez-utils \
  qt6-5compat qt6-avif-image-plugin qt6-imageformats qt6-multimedia \
  qt6-positioning qt6-quicktimeline qt6-sensors qt6-tools \
  qt6-translations qt6-virtualkeyboard qt6-wayland \
  kirigami syntax-highlighting 2>/dev/null || \
yay -S --noconfirm --needed \
  git jq curl bluez-utils \
  qt6-5compat qt6-avif-image-plugin qt6-imageformats qt6-multimedia \
  qt6-positioning qt6-quicktimeline qt6-sensors qt6-tools \
  qt6-translations qt6-virtualkeyboard qt6-wayland \
  kirigami syntax-highlighting
remove_fallback_mirror

# Build and install mainstream-quickshell-git from the stored (patched) PKGBUILD.
# The patch removes the cpptrace dependency (only used for crash reporting) and
# passes -DCRASH_HANDLER=OFF to cmake, so the build has no unavailable AUR deps.
# We force-remove the stock quickshell first since they conflict.
# Match the exact installed package name: pacman -Qi resolves "provides", so it
# would report our own mainstream-quickshell-git (Provides: quickshell) as a
# match, but pacman -R can't resolve provides and would fail with
# "target not found: quickshell" on re-runs. Grep the exact name instead.
if pacman -Qq | grep -qx quickshell; then
  sudo pacman -Rdd --noconfirm quickshell
fi
builddir="$(mktemp -d)"
cp "$SCRIPT_DIR/quickshell/PKGBUILD" "$builddir/"
cp "$SCRIPT_DIR/quickshell/quickshell-check.hook" "$builddir/"
(cd "$builddir" && makepkg -si --noconfirm)
rm -rf "$builddir"

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
