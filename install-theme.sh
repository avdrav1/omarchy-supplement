#!/bin/bash

set -euo pipefail

# Apply the Dos-Moos Omarchy theme and (on Omarchy 3 only) install the
# Quickshell Rise bar.
# - Dos-Moos theme:      https://github.com/HANCORE-linux/omarchy-dos-moos-theme
# - Quickshell Rise bar: https://github.com/HANCORE-linux/quickshell-dots

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# ── Quickshell Rise bar (Omarchy 3 only) ─────────────────────────────────────
# The Rise bar replaces waybar, which is only the bar on Omarchy 3. Omarchy 4
# (quattro) ships its own quickshell-based shell -- omarchy-shell / omarchy-bar
# -- and the omarchy package *depends on* quickshell-git. Our pinned
# mainstream-quickshell-git declares conflicts=(quickshell quickshell-git) and
# is an older commit than what omarchy 4 ships, so installing it there means
# either a hard pacman conflict or downgrading the package omarchy's own shell
# runs on. Detect via omarchy-shell: present == omarchy owns quickshell.
if command -v omarchy-shell >/dev/null 2>&1; then
  echo "Omarchy 4+ detected (omarchy-shell present) -- skipping Quickshell Rise bar."
  echo "Omarchy's own shell already owns quickshell; installing Rise here would"
  echo "conflict with / downgrade quickshell-git out from under omarchy-bar."
  exit 0
fi

echo "Installing Quickshell Rise bar..."

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
# We force-remove any stock quickshell first since they conflict.
# Match exact installed package names: pacman -Qi resolves "provides", so it
# would report our own mainstream-quickshell-git (Provides: quickshell) as a
# match, but pacman -R can't resolve provides and would fail with
# "target not found: quickshell" on re-runs. Grep exact names instead -- and
# check both, since the PKGBUILD conflicts with quickshell AND quickshell-git.
for pkg in quickshell quickshell-git; do
  if pacman -Qq | grep -qx "$pkg"; then
    sudo pacman -Rdd --noconfirm "$pkg"
  fi
done
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
