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
  vesktop-bin          # AUR: Discord client (SUPER+D and autostart in hypr/lua/apps.lua)
  perplexity           # omarchy repo
  godot                # extra
  android-tools        # extra: adb/fastboot
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

# Steam through Omarchy's own pieces rather than a bare package: the lib32 GPU
# drivers have to go in first, or pacman resolves Steam's virtual
# lib32-vulkan-driver to lib32-nvidia-utils on every machine. Not
# omarchy-install-gaming-steam itself, which launches Steam when it finishes.
if ! pacman -Qq steam &>/dev/null; then
  echo "Installing Steam"
  omarchy-install-gaming-gpu-lib32
  omarchy-pkg-add steam
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
add_webapp "Bisco Radio" "https://biscomusic.com" "$ICONS/bisco-radio.png"

# ── Apps from upstream install scripts ───────────────────────────────────────
# No package for these; each vendor's script drops a binary (plus a .desktop
# entry for the GUI ones) into ~/.local/bin. None of them prompt. Skipped when
# the command already exists -- they update themselves, or are re-run by hand.
script_app() {
  local cmd="$1" url="$2"
  shift 2
  if command -v "$cmd" >/dev/null 2>&1 || [ -x "$HOME/.local/bin/$cmd" ]; then
    echo "'$cmd' already installed."
    return
  fi
  echo "Installing '$cmd' ($url)"
  curl -fsSL "$url" | sh -s -- "$@" ||
    echo "  warning: could not install '$cmd'" >&2
}

script_app zed https://zed.dev/install.sh
script_app herdr https://herdr.dev/install.sh               # terminal multiplexer
script_app omp https://omp.sh/install                       # oh-my-pi coding agent
script_app tidemail https://raw.githubusercontent.com/allisonhere/tidemail/main/install.sh
script_app llmfit https://llmfit.axjns.dev/install.sh --local # --local: no sudo prompt
script_app gutenberg https://gutenbergapp.com/install.sh   # news reader
script_app brick https://brick.cronkite.cc/install.sh      # spreadsheet
script_app slate https://slate.cronkite.cc/install.sh
script_app frame https://frame.cronkite.cc/install.sh
script_app etch https://etch.cronkite.cc/install.sh        # image editor

# Gutenberg's installer drops only the binary, so give it a launcher entry.
# StartupWMClass matches the application_id it sets on its window.
if [ -x "$HOME/.local/bin/gutenberg" ] && [ ! -f "$APPS_DIR/gutenberg.desktop" ]; then
  install -Dm644 "$SCRIPT_DIR/apps/icons/gutenberg.svg" \
    "$HOME/.local/share/icons/hicolor/scalable/apps/gutenberg.svg"
  cat >"$APPS_DIR/gutenberg.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Gutenberg
GenericName=News Reader
Comment=Read feeds and articles
Exec=$HOME/.local/bin/gutenberg
Icon=gutenberg
Terminal=false
StartupWMClass=gutenberg
Categories=Network;News;
Keywords=rss;atom;feed;news;reader;
EOF
  echo "Added the Gutenberg launcher entry."
fi

# Kimi Code CLI: a wrapper that runs the npm package through mise.
if [ ! -x "$HOME/.local/bin/kimi" ]; then
  install -Dm755 "$SCRIPT_DIR/bin/kimi" "$HOME/.local/bin/kimi"
  echo "Installed the kimi wrapper."
fi

# Omarchy iCloud Photos (recent iCloud photos in a launcher, plus a sync timer).
# The checkout sits under ~/Documents, as on the reference machine, so a machine
# that Syncthing already gave it to just re-links it. Its install.sh symlinks
# into the checkout and is re-runnable. The Apple sign-in is per machine.
ICLOUD_SRC="$HOME/Documents/github.com/jankeesvw/omarchy-icloud-photos"
if [ ! -d "$ICLOUD_SRC" ]; then
  git clone --quiet https://github.com/jankeesvw/omarchy-icloud-photos.git "$ICLOUD_SRC" ||
    echo "  warning: could not clone omarchy-icloud-photos" >&2
fi
if [ -x "$ICLOUD_SRC/install.sh" ] && [ ! -e "$HOME/.local/bin/omarchy-icloud-photos" ]; then
  "$ICLOUD_SRC/install.sh" || echo "  warning: omarchy-icloud-photos install failed" >&2
fi

echo "Apps installation complete."
