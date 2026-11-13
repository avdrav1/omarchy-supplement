#!/bin/bash
# Strata file manager in place of Omarchy's Folio (folders, "Show in folder", file picker)
source "$(dirname "$0")/../lib/common.sh"

# Strata (https://github.com/lgse/strata) isn't packaged. Upstream's release
# installer verifies the signed release manifest and the archive digest, then
# installs ~/.local/bin/strata, its desktop entry, the FileManager1 D-Bus
# service ("Show in folder") and the FileChooser portal. After that Strata
# updates itself (Settings -> Updates), so the installer only runs when the
# binary is missing.
STRATA="$HOME/.local/bin/strata"
APP_ID="io.github.lgse.Strata"

step "Strata"
# Seeded before the first launch: Strata only follows the Omarchy theme on its
# own while no settings file exists, and it refuses to save through a symlink.
seed "$CONFIG/strata/settings.toml" "$HOME/.config/strata/settings.toml"

if [ ! -x "$STRATA" ]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  base="https://github.com/lgse/strata/releases/latest/download"
  curl -fsSL -o "$tmp/install.sh" "$base/install.sh"
  curl -fsSL -o "$tmp/install.sh.sha256" "$base/install.sh.sha256"
  (cd "$tmp" && sha256sum --check --quiet install.sh.sha256)
  # Keybinds are ours (config/hypr/bindings.lua), not appended to Omarchy's file.
  bash "$tmp/install.sh" --non-interactive --without-omarchy-keybinds
fi

# The installer claims inode/directory only. The rest point at Folio (or
# nothing) on a fresh Omarchy, and file:// is what browsers' "Show in folder"
# falls back to without the portal. Archives stay with whatever opens them:
# handed a .zip, Strata just reveals it.
for mime in inode/directory x-directory/normal inode/mount-point \
  x-scheme-handler/file x-scheme-handler/trash; do
  [ "$(xdg-mime query default "$mime")" = "$APP_ID.desktop" ] ||
    xdg-mime default "$APP_ID.desktop" "$mime"
done

# Folio is an Omarchy base package; with Strata in its place it's only a second
# claimant for the same MIME types.
if has_pkg folio; then
  note "removing folio"
  sudo pacman -Rns --noconfirm folio
fi
