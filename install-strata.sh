#!/bin/bash

# Install Strata: a fast, keyboard-first Miller-column file manager for Linux.
#   https://github.com/lgse/strata
#
# Strata is not in the AUR -- upstream ships precompiled, attested tarballs on
# GitHub Releases -- so this installer fetches a release directly rather than
# going through yay. That also means there is no pacman/yay bookkeeping to lean
# on for "is it current?", hence the version stamp below.
#
# Hyprland wiring (the SUPER+SHIFT+F binds) lives in hypr/lua/bindings.lua and
# is applied by install-hyprland-overrides.sh -- deliberately Lua-tree only, see
# the NOTE beside the eDP-1 binds in hyprland-overrides.conf for why.
#
# Config arrived in 0.7.0 (~/.config/strata/settings.toml, plus custom themes in
# themes/); 0.4.0, which this script first targeted, had none. It is seeded from
# strata/settings.toml in this repo rather than stowed from the dotfiles repo --
# see the comment at the seeding block below for why a symlink is not merely
# overwritten but breaks the app's ability to save preferences at all.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="lgse/strata"
PREFIX="$HOME/.local/bin"
# Upstream publishes no --version flag (`strata --version` prints "Unknown
# option"), and the binary is the only artifact, so there is nothing to
# interrogate for the installed version. Stamp it ourselves instead, and treat a
# missing stamp as "unknown" so the next run reinstalls rather than guessing.
STAMP="$HOME/.local/share/strata/installed-version"
DESKTOP_ID="io.github.lgse.Strata.desktop"
DESKTOP_FILE="$HOME/.local/share/applications/$DESKTOP_ID"
CONFIG_DIR="$HOME/.config/strata"
SETTINGS="$CONFIG_DIR/settings.toml"
SETTINGS_TEMPLATE="$SCRIPT_DIR/strata/settings.toml"

# ── Runtime dependencies ─────────────────────────────────────────────────────
# All official-repo packages, so pacman rather than yay. bubblewrap sandboxes
# preview rendering; the ffmpeg/poppler/gtksourceview trio backs video, PDF and
# source-code thumbnails. Guarded as a set: `pacman -Qi` on the whole list exits
# non-zero if *any* is missing, and a bare `pacman -S` would otherwise
# pre-authenticate via sudo on every run -- which fails in a non-interactive
# provision and lands in install-all.sh's failure summary on an already-current
# machine.
# gst-libav/gst-plugins-good back the GStreamer video preview path and gvfs-smb
# enables SMB browsing from Ctrl+L; both were added to upstream's dependency list
# after 0.4.0. Missing them degrades silently (a blank video preview, an smb://
# address that never resolves) rather than failing at startup, which is exactly
# why they are pinned here.
DEPS=(bubblewrap ffmpeg ffmpegthumbnailer fontconfig gst-libav gst-plugins-good
      gtk4 gtksourceview5 gvfs-smb poppler-glib)
if ! pacman -Qi "${DEPS[@]}" &>/dev/null; then
  sudo pacman -S --noconfirm --needed "${DEPS[@]}"
fi

# ── Resolve the latest release ───────────────────────────────────────────────
case "$(uname -m)" in
  x86_64)  TARGET="x86_64-unknown-linux-gnu" ;;
  aarch64) TARGET="aarch64-unknown-linux-gnu" ;;
  *) echo "strata: no upstream build for $(uname -m); skipping." >&2; exit 0 ;;
esac

# Resolve the tag from the API rather than hardcoding it, so a re-run picks up
# new releases. Non-fatal on failure: an offline or rate-limited machine that
# already has Strata should not fail the provision.
TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
  | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"

if [ -z "$TAG" ]; then
  if command -v strata &>/dev/null; then
    echo "strata: cannot reach the GitHub API; keeping the installed build."
    exit 0
  fi
  echo "strata: cannot reach the GitHub API and strata is not installed." >&2
  exit 1
fi

VERSION="${TAG#v}"

if [ -x "$PREFIX/strata" ] && [ "$(cat "$STAMP" 2>/dev/null || true)" = "$VERSION" ]; then
  echo "strata $VERSION already installed."
else
  echo "Installing strata $VERSION ($TARGET)..."

  ARCHIVE="strata-$VERSION-$TARGET.tar.gz"
  BASE="https://github.com/$REPO/releases/download/$TAG"
  # Work in a scratch dir so a failed verification never leaves a half-installed
  # binary behind, and so re-runs don't accumulate tarballs in ~/Downloads.
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  curl -fsSL -o "$TMP/$ARCHIVE" "$BASE/$ARCHIVE"
  curl -fsSL -o "$TMP/$ARCHIVE.sha256" "$BASE/$ARCHIVE.sha256"

  # Checksum is fatal: these are prebuilt binaries from a third party, and a
  # mismatch means the download is corrupt or tampered with.
  ( cd "$TMP" && sha256sum --check --quiet "$ARCHIVE.sha256" )

  # Provenance is best-effort. It proves the tarball came from upstream's GitHub
  # Actions build, but needs gh installed AND authenticated, which is not true
  # on a machine being provisioned from scratch (gh arrives via mise). Warn
  # loudly rather than blocking the install -- the checksum above already
  # covers download integrity.
  if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    if gh attestation verify "$TMP/$ARCHIVE" --repo "$REPO" >/dev/null 2>&1; then
      echo "strata: build provenance verified."
    else
      echo "!! strata: attestation verification FAILED for $ARCHIVE." >&2
      echo "!! Refusing to install. Check https://github.com/$REPO/releases" >&2
      exit 1
    fi
  else
    echo "strata: gh unavailable or not authenticated; skipped the attestation"
    echo "        check (checksum verified). Re-run after 'gh auth login' to"
    echo "        confirm build provenance."
  fi

  tar -xzf "$TMP/$ARCHIVE" -C "$TMP"
  install -Dm755 "$TMP/strata-$VERSION-$TARGET/strata" "$PREFIX/strata"

  mkdir -p "$(dirname "$STAMP")"
  echo "$VERSION" >"$STAMP"
  echo "strata $VERSION installed to $PREFIX/strata"
fi

# ── User configuration ───────────────────────────────────────────────────────
# Strata 0.7.0 added ~/.config/strata/settings.toml and custom themes in
# ~/.config/strata/themes/. Both are SEEDED as real files and then owned by the
# app -- never symlinked, and so deliberately not part of install-dotfiles.sh.
#
# The reason is not just that Strata rewrites settings.toml on every change in
# Settings (Ctrl+,). It is that the write goes through storage::atomic_write,
# which stats the destination with symlink_metadata and bails on anything that
# is not a regular file ("refusing to replace non-regular destination"). Against
# a stow symlink the save does not fall through to the link target and does not
# replace the link -- it simply fails, and only into a tracing::warn the UI never
# shows. Every preference change would appear to work and be lost on restart.
#
# Seed-if-absent, so a provision run never discards settings changed in the app.
mkdir -p "$CONFIG_DIR"
# Custom palettes are read from here at startup (see docs/themes.md upstream).
# Nothing is shipped: on Omarchy Quattro the seeded `mode = "omarchy"` makes
# Strata track the active Omarchy theme directly, so a checked-in copy of that
# palette would only duplicate it and drift. The directory is created so the
# drop-in location is obvious, and so the in-app theme editor writes to a real
# directory rather than creating one.
mkdir -p "$CONFIG_DIR/themes"

if [ -L "$SETTINGS" ]; then
  # Not repaired automatically: the link may be tracked by a dotfiles repo, and
  # dereferencing it here would silently detach it. Report and continue.
  echo "!! strata: $SETTINGS is a symlink." >&2
  echo "!! Strata cannot save preferences through it -- every change in Settings" >&2
  echo "!! is discarded with only a log warning. Replace it with a real file:" >&2
  echo "!!   cp --remove-destination \"\$(readlink -f \"$SETTINGS\")\" \"$SETTINGS\"" >&2
elif [ -e "$SETTINGS" ]; then
  echo "strata: keeping the existing $SETTINGS."
elif [ -f "$SETTINGS_TEMPLATE" ]; then
  install -Dm644 "$SETTINGS_TEMPLATE" "$SETTINGS"
  echo "strata: seeded $SETTINGS (follows the Omarchy theme; edit in-app with Ctrl+,)."
else
  # Only reachable if this script was copied out of the repo on its own. Strata
  # defaults to following Omarchy when no settings file exists, so this is a
  # degraded-but-correct outcome, not a failure.
  echo "strata: $SETTINGS_TEMPLATE not found; leaving Strata on its own defaults."
fi

# ── Desktop entry + folder handler ───────────────────────────────────────────
# Generated here rather than stowed from the dotfiles repo: it is derived from
# the install (and rewritten whenever this script changes it), not hand-edited
# config. Exec is the bare binary name so the entry stays host-independent --
# ~/.local/bin is on PATH for the graphical session via the login shell.
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
# Managed by install-strata.sh -- edits here are overwritten on the next run.
Name=Strata
Comment=Navigate every layer
Exec=strata %U
Icon=system-file-manager
Terminal=false
Type=Application
Categories=Utility;FileManager;
MimeType=inode/directory;
StartupNotify=true
EOF

update-desktop-database "$(dirname "$DESKTOP_FILE")" 2>/dev/null || true

# Make Strata the handler for folders opened by other applications. This is what
# makes it the file manager on legacy (hyprlang) machines too, where the
# SUPER+SHIFT+F bind is not available -- see the NOTE in hyprland-overrides.conf.
PREV_HANDLER="$(xdg-mime query default inode/directory 2>/dev/null || true)"
xdg-mime default "$DESKTOP_ID" inode/directory

if [ "$PREV_HANDLER" = "$DESKTOP_ID" ]; then
  echo "strata: already the inode/directory handler."
else
  echo "strata: now the inode/directory handler (was: ${PREV_HANDLER:-none})."
fi
echo "strata installation complete."
