#!/bin/bash

# Install QuickSwitch -- a macOS-style task switcher for Omarchy/Hyprland, with
# a still snapshot of every window and its app icon in a strip across the
# screen. Hold SUPER, tap TAB (or the arrows) to advance, release to switch to
# the selected window's workspace. SUPER+Q quits the highlighted app.
#   Upstream: https://github.com/ewweberlin/QuickSwitch
#
# This is an omarchy-shell PLUGIN (QML hosted by the long-running Quickshell
# process), not a package -- there is nothing in the AUR to install and no
# systemd unit. `omarchy plugin add` clones it into ~/.config/omarchy/plugins
# and --enable registers it, so this script is a thin, idempotent wrapper.
#
# Hyprland wiring (SUPER+TAB and the arrow keys) is NOT here: it lives in
# hypr/lua/quickswitch.lua and is applied by install-hyprland-overrides.sh.
# Read that file's header before touching the binds -- the load ordering against
# supplement.bindings is the whole reason this works.
#
# SUPER+TAB is taken off Omarchy's "next workspace" default to make room.
# ALT+TAB is left alone and keeps Omarchy's stock cycle-next behavior. The Lua
# module no-ops when the plugin directory is absent, so a machine that skips
# this script is unaffected.
#
# Overridable per machine:
#   QUICKSWITCH_SKIP=1    skip it entirely on this machine

set -euo pipefail

PLUGIN_REPO_URL="https://github.com/ewweberlin/QuickSwitch.git"
PLUGIN_ID="ewweberlin.quickswitch"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
MIN_HYPRLAND="0.56"

if [ "${QUICKSWITCH_SKIP:-0}" != 0 ]; then
  echo "install-quickswitch: QUICKSWITCH_SKIP set; skipping."
  exit 0
fi

# Omarchy's bin dir is not guaranteed on PATH in a non-interactive run; without
# it the plugin calls below would silently do nothing.
for d in "$HOME/.local/share/omarchy/bin" /usr/share/omarchy/bin; do
  [ -d "$d" ] && PATH="$d:$PATH"
done
export PATH

# ── Preconditions ────────────────────────────────────────────────────────────
# All three are silent failures rather than errors if we let them through: the
# plugin would install and simply never open.
if ! command -v omarchy >/dev/null 2>&1; then
  echo "install-quickswitch: the omarchy CLI is not on PATH; skipping." >&2
  exit 0
fi

# The plugin's bindings file is Lua (hl.unbind / o.bind). A machine still on the
# hyprlang (.conf) parser cannot load it at all, and hypr/lua/ is not even wired
# up there -- see the header of install-hyprland-overrides.sh.
if [ ! -f "$HOME/.config/hypr/hyprland.lua" ]; then
  echo "install-quickswitch: this machine is on the hyprlang (.conf) config;" >&2
  echo "  QuickSwitch needs the Lua parser. Skipping." >&2
  exit 0
fi

hypr_version="$(hyprctl version 2>/dev/null | sed -n 's/^Hyprland \([0-9.]*\).*/\1/p' | head -1)"
if [ -n "$hypr_version" ] && (($(vercmp "$hypr_version" "$MIN_HYPRLAND") < 0)); then
  echo "install-quickswitch: needs Hyprland >= $MIN_HYPRLAND for the Lua config" >&2
  echo "  and toplevel-export previews; this machine has $hypr_version. Skipping." >&2
  exit 0
fi

# ── Install / update ─────────────────────────────────────────────────────────
if [ -d "$PLUGIN_DIR/.git" ]; then
  echo "Updating the $PLUGIN_ID plugin..."
  omarchy plugin update "$PLUGIN_ID" --yes
else
  echo "Installing the $PLUGIN_ID plugin..."
  # Omarchy adds third-party plugins disabled. --enable is what appends
  # {"id": "..."} to shell.json's `plugins` array, and for a service plugin
  # that array IS the enablement -- unlike a bar widget there is no layout
  # entry to place, so nothing here has to touch bar.layout or Shibumi's
  # group layout.
  omarchy plugin add "$PLUGIN_REPO_URL" --enable --yes
fi

[ -f "$PLUGIN_DIR/manifest.json" ] || {
  echo "ERROR: $PLUGIN_ID did not install to $PLUGIN_DIR" >&2
  exit 1
}

# `plugin add --enable` normally handles this; re-assert it because `plugin
# update` does not, and a plugin left out of shell.json loads for nobody.
# No --yes here: the signature is `plugin enable <id> [placement]`, so a --yes
# would be parsed as a placement. Bare is right anyway -- placement is for bar
# widgets, and this is a service plugin with nothing to place.
omarchy plugin enable "$PLUGIN_ID" >/dev/null 2>&1 || true

# ── Verify ───────────────────────────────────────────────────────────────────
# shell.json hot-reloads, but plugin *code* is only re-read on request.
# Non-fatal: omarchy-shell may simply not be running (e.g. a provision run
# outside a graphical session).
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

if ! python3 - "$HOME/.config/omarchy/shell.json" "$PLUGIN_ID" <<'PY'
import json, sys
path, plugin_id = sys.argv[1], sys.argv[2]
try:
    cfg = json.load(open(path))
except (OSError, ValueError):
    raise SystemExit(1)
entries = cfg.get("plugins") or []
ids = {e.get("id") if isinstance(e, dict) else e for e in entries}
disabled = set(cfg.get("disabledPlugins") or [])
raise SystemExit(0 if plugin_id in ids and plugin_id not in disabled else 1)
PY
then
  echo "  warning: $PLUGIN_ID is not enabled in shell.json; the shell will not" >&2
  echo "  load it. Enable it from Setup > Plugins." >&2
fi

cat <<EOF

QuickSwitch installed.

  SUPER+TAB   open the switcher; tap TAB or the arrows (holding SUPER) to
              advance, release SUPER to switch. SUPER+Q quits the highlighted
              app while it is open.
  ALT+TAB     unchanged -- Omarchy's stock "focus next window".

The binds come from hypr/lua/quickswitch.lua, applied by
./install-hyprland-overrides.sh. If SUPER+TAB still cycles workspaces, that
script has not run since this one; run it, then \`hyprctl reload\`.

Verify:  omarchy menu keybindings --print | grep -i 'TAB'   # -> "Task switch"
         hyprctl globalshortcuts | grep quickswitch          # -> 5 entries
EOF
