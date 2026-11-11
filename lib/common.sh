# shellcheck shell=bash
# Shared helpers, sourced by ./setup and by every module in modules/.
#
# Everything here is idempotent: each helper checks first and only acts (or
# reaches for sudo) when something is actually missing, so re-running a module
# on a provisioned machine is a quiet no-op.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO/config"
ASSETS="$REPO/assets"
MANIFEST="$REPO/manifest"

# Omarchy's bin dir is not guaranteed to be on PATH in a non-interactive run.
for _d in "$HOME/.local/share/omarchy/bin" /usr/share/omarchy/bin; do
  [ -d "$_d" ] && PATH="$_d:$PATH"
done
unset _d
export PATH

# ── Output ───────────────────────────────────────────────────────────────────
step() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die() {
  printf '!! %s\n' "$*" >&2
  exit 1
}

# ── Manifests ────────────────────────────────────────────────────────────────
# Print a manifest file with comments and blank lines stripped.
manifest() { sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$MANIFEST/$1"; }

# ── Packages ─────────────────────────────────────────────────────────────────
has_pkg() { pacman -Qq "$1" &>/dev/null; }

# Install repo or AUR packages that are not already installed. Filtering first
# matters: `yay --needed` still runs sudo pacman even when nothing is missing.
# Retries because the AUR RPC endpoint intermittently resets connections.
pkg() {
  local missing=() p attempt
  for p in "$@"; do has_pkg "$p" || missing+=("$p"); done
  ((${#missing[@]})) || return 0
  note "installing ${missing[*]}"
  for attempt in 1 2 3; do
    yay -S --noconfirm --needed "${missing[@]}" && return 0
    ((attempt < 3)) && { warn "yay failed (attempt $attempt/3); retrying in 5s"; sleep 5; }
  done
  return 1
}

# Run an Omarchy installer (`omarchy install <args>`) unless <cmd> already
# exists as a command or as a launcher (some installers make a web app instead,
# e.g. Spotify on ARM). Omarchy's installers usually open the app when they finish.
omarchy_install() {
  local cmd="$1"
  shift
  command -v "$cmd" &>/dev/null || [ -x "$HOME/.local/bin/$cmd" ] && return 0
  [ -n "$(find "$HOME/.local/share/applications" -maxdepth 1 -iname "$cmd.desktop" 2>/dev/null)" ] && return 0
  note "omarchy install $*"
  omarchy install "$@"
}

# ── Services ─────────────────────────────────────────────────────────────────
user_service() {
  systemctl --user is-enabled --quiet "$1" 2>/dev/null && systemctl --user is-active --quiet "$1" && return 0
  systemctl --user enable --now "$1" || warn "could not enable $1"
}

system_service() {
  systemctl is-enabled --quiet "$1" 2>/dev/null && systemctl is-active --quiet "$1" && return 0
  sudo systemctl enable --now "$1"
}

# ── Files ────────────────────────────────────────────────────────────────────
# Copy a file into place only when nothing is there yet. Used for settings an
# app rewrites itself: a symlink would be replaced (or refused) on first save,
# so these are seeded once and then belong to the app.
seed() {
  local src="$1" dst="$2" mode="${3:-644}"
  [ -e "$dst" ] && return 0
  install -Dm"$mode" "$src" "$dst"
  note "seeded $dst"
}

# Write stdin to <dst> only when the content differs. Prefix with SUDO=1 for
# root-owned paths; an identical file never costs a sudo.
put() {
  local dst="$1" tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  if cmp -s "$tmp" "$dst" 2>/dev/null; then
    rm -f "$tmp"
    return 0
  fi
  if [ "${SUDO:-0}" = 1 ]; then
    sudo install -Dm644 "$tmp" "$dst"
  else
    install -Dm644 "$tmp" "$dst"
  fi
  rm -f "$tmp"
  note "wrote $dst"
}

# ── Omarchy shell ────────────────────────────────────────────────────────────
SHELL_JSON="$HOME/.config/omarchy/shell.json"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"

in_session() { [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; }
