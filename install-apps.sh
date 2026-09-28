#!/bin/bash

set -euo pipefail

# Desktop apps and web apps the reference machine (alienware) has that are not
# part of Omarchy's base install and have no installer of their own here.
#
# Packages are installed with --needed, so a re-run is a no-op on a machine that
# already has them. Sign-in is per machine for all of these (1Password, Discord
# and the Codex app keep their accounts in their own profile dirs).
#
# Packages that exist only to back a bar widget (qbittorrent-nox, nordvpn-bin,
# the Omastat daemon) are NOT here -- install-bar-plugins.sh owns them, next to
# the widget that needs them.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PACKAGES=(
  1password            # omarchy repo
  1password-cli        # `op`
  discord              # extra
  openai-codex-desktop # omarchy repo
  clock-tui-bin        # AUR: `tclock`
)

# Filter to what is missing first: `yay --needed` still hands repo packages to
# `sudo pacman` even when every one is installed, so a re-run on a provisioned
# machine would need root (and fail with no tty) just to do nothing.
MISSING=()
for pkg in "${PACKAGES[@]}"; do
  pacman -Qq "$pkg" &>/dev/null || MISSING+=("$pkg")
done
if ((${#MISSING[@]})); then
  echo "Installing apps: ${MISSING[*]}"
  yay -S --noconfirm --needed "${MISSING[@]}"
else
  echo "Apps already installed: ${PACKAGES[*]}"
fi

# ── Web apps ─────────────────────────────────────────────────────────────────
# Omarchy's stock web apps (HEY, Basecamp, WhatsApp, YouTube, ...) come from its
# own installer; these are the extras. Icons are tracked in webapps/icons/ so
# every machine gets the same one; an empty icon argument makes
# omarchy-webapp-install fetch the site's own icon instead (nugs, whose icon on
# the reference machine is a broken 1x1 placeholder).
#
# Skipped when the .desktop already exists, so a re-run does not overwrite an
# icon or URL that was changed by hand on that machine.
APPS_DIR="$HOME/.local/share/applications"
ICONS="$SCRIPT_DIR/webapps/icons"

add_webapp() {
  local name="$1" url="$2" icon="$3"
  if [ -f "$APPS_DIR/$name.desktop" ]; then
    echo "Web app '$name' already exists."
    return
  fi
  echo "Adding web app '$name' ($url)"
  omarchy-webapp-install "$name" "$url" "$icon" ||
    echo "  warning: could not create web app '$name'" >&2
}

add_webapp amazon "https://amazon.com" "$ICONS/amazon.png"
add_webapp netflix "https://netflix.com" "$ICONS/netflix.png"
add_webapp nugs "https://nugs.net" ""

echo "Apps installation complete."
