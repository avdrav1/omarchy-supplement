#!/bin/bash

# Starship prompt + the upstream "pastel-powerline" preset.
#
#   https://starship.rs/presets/pastel-powerline
#
# The config is GENERATED from the installed starship binary rather than
# vendored here, so it always matches the preset shipped with that version
# instead of drifting against a stale copy.
#
# MUST run AFTER install-dotfiles.sh. The dotfiles repo used to own
# ~/.config/starship.toml via `stow starship`; that package is no longer stowed
# (see install-dotfiles.sh), but a machine provisioned before that change still
# has the stow symlink in place -- and writing the preset *through* it would
# silently rewrite the tracked file inside ~/dotfiles.

set -u

if ! command -v starship &>/dev/null; then
  echo "Installing Starship..."
  yay -S --noconfirm --needed starship || exit 1
fi

CONFIG="$HOME/.config/starship.toml"
mkdir -p "$(dirname "$CONFIG")"

# Generate BEFORE touching the existing config, so a failure here leaves the
# machine with whatever prompt config it already had rather than none.
#
# Capture stdout rather than using `starship preset -o "$TMP"`: with -o starship
# refuses to write to a path that already exists ("use --force to overwrite"),
# and mktemp has by definition already created it.
TMP=$(mktemp) || exit 1
trap 'rm -f "$TMP"' EXIT
if ! starship preset pastel-powerline > "$TMP" || [ ! -s "$TMP" ]; then
  echo "!! Failed to generate the pastel-powerline preset ($(starship --version 2>/dev/null | head -1))." >&2
  exit 1
fi

# A symlink here is a leftover `stow starship` from the dotfiles repo (see the
# header). Always replace it with a real file -- writing through it would
# silently rewrite the tracked file inside ~/dotfiles.
if [ ! -L "$CONFIG" ] && [ -f "$CONFIG" ] && cmp -s "$TMP" "$CONFIG"; then
  echo "Starship pastel-powerline preset already installed at $CONFIG"
else
  if [ -L "$CONFIG" ]; then
    echo "Removing stow symlink $CONFIG -> $(readlink -f "$CONFIG")"
    rm -f "$CONFIG"
  elif [ -f "$CONFIG" ] && [ ! -f "$CONFIG.pre-preset" ]; then
    # Keep one copy of whatever hand-rolled config was there before the first
    # run of this installer. Guarded on absence so re-runs never overwrite the
    # original backup with an already-generated preset.
    cp -- "$CONFIG" "$CONFIG.pre-preset"
    echo "Backed up previous config to $CONFIG.pre-preset"
  fi
  cp -- "$TMP" "$CONFIG"
  echo "Installed Starship pastel-powerline preset to $CONFIG"
fi

# The preset's powerline separators and language glyphs are Nerd Font
# codepoints -- without one the prompt renders as tofu boxes. Warn only; the
# font is part of the base Omarchy install, not this installer's job.
if ! pacman -Qq 2>/dev/null | grep -qi 'nerd'; then
  echo "WARNING: no Nerd Font package detected. pastel-powerline needs one" >&2
  echo "         (e.g. ttf-jetbrains-mono-nerd) or the prompt shows tofu." >&2
fi
