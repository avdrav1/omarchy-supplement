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
# the NOTE beside the eDP-1 binds in hyprland-overrides.conf for why. Nothing
# ships from the dotfiles repo: Strata 0.4.0 has no user config file.

set -euo pipefail

REPO="lgse/strata"
PREFIX="$HOME/.local/bin"
# Upstream publishes no --version flag (`strata --version` prints "Unknown
# option"), and the binary is the only artifact, so there is nothing to
# interrogate for the installed version. Stamp it ourselves instead, and treat a
# missing stamp as "unknown" so the next run reinstalls rather than guessing.
STAMP="$HOME/.local/share/strata/installed-version"
DESKTOP_ID="io.github.lgse.Strata.desktop"
DESKTOP_FILE="$HOME/.local/share/applications/$DESKTOP_ID"

# ── Runtime dependencies ─────────────────────────────────────────────────────
# All official-repo packages, so pacman rather than yay. bubblewrap sandboxes
# preview rendering; the ffmpeg/poppler/gtksourceview trio backs video, PDF and
# source-code thumbnails. Guarded as a set: `pacman -Qi` on the whole list exits
# non-zero if *any* is missing, and a bare `pacman -S` would otherwise
# pre-authenticate via sudo on every run -- which fails in a non-interactive
# provision and lands in install-all.sh's failure summary on an already-current
# machine.
DEPS=(bubblewrap ffmpeg ffmpegthumbnailer fontconfig gtk4 gtksourceview5 poppler-glib)
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
