#!/bin/bash

set -euo pipefail

# Make `fresh` (fresh-editor: a terminal text editor with multi-cursor support)
# the default editor for the whole Wayland/uwsm session, so TUIs like aerc open
# compose buffers in it instead of the Omarchy default (zeditor/Zed).
#
# Why uwsm/default and not hypr/envs.conf: apps are launched via `uwsm app`
# (terminals, walker, keybinds), so they inherit the *systemd user* environment
# that uwsm populates from ~/.config/uwsm/default — that value wins over
# Hyprland's `env =` directives. So the editor must be set here to take effect.

EDITOR_CMD="${EDITOR_CMD:-fresh}"

# Install fresh-editor (AUR) unless another editor command was requested.
if [ "$EDITOR_CMD" = "fresh" ]; then
  if pacman -Qi fresh-editor-bin &>/dev/null; then
    echo "fresh-editor already installed."
  else
    yay -S --noconfirm --needed fresh-editor-bin
  fi
fi

UWSM_DEFAULT="$HOME/.config/uwsm/default"
if [ ! -f "$UWSM_DEFAULT" ]; then
  echo "No $UWSM_DEFAULT (uwsm not set up?); skipping editor default."
  exit 0
fi

# Idempotently set EDITOR and VISUAL to $EDITOR_CMD, replacing any existing
# export (e.g. the stock `export EDITOR=zeditor`) rather than appending dupes.
set_export() {
  local var="$1" val="$2"
  if grep -qE "^export ${var}=" "$UWSM_DEFAULT"; then
    sed -i "s|^export ${var}=.*|export ${var}=${val}|" "$UWSM_DEFAULT"
  else
    printf 'export %s=%s\n' "$var" "$val" >>"$UWSM_DEFAULT"
  fi
}
set_export EDITOR "$EDITOR_CMD"
set_export VISUAL "$EDITOR_CMD"

# Apply to the running session too, so it takes effect without a relog. Already
# open apps keep their old env until restarted.
if command -v systemctl &>/dev/null; then
  systemctl --user set-environment EDITOR="$EDITOR_CMD" VISUAL="$EDITOR_CMD" 2>/dev/null || true
fi

# Point Omarchy's editor keybind (SUPER+SHIFT+N -> omarchy-launch-editor) at the
# same editor. That launcher reads this state file and otherwise falls back to
# nvim; `fresh` is on its TUI whitelist so it opens via omarchy-launch-tui.
# We write the file directly because omarchy-default-editor rejects `fresh` as
# an argument (its case list predates fresh-editor).
OMARCHY_EDITOR_STATE="$HOME/.local/state/omarchy/defaults/editor"
mkdir -p "$(dirname "$OMARCHY_EDITOR_STATE")"
printf '%s\n' "$EDITOR_CMD" >"$OMARCHY_EDITOR_STATE"
echo "Omarchy default editor (SUPER+SHIFT+N) set to '$EDITOR_CMD'."

echo "Default editor set to '$EDITOR_CMD' (EDITOR + VISUAL) in uwsm/default."
echo "Restart aerc / your terminal to pick it up."
