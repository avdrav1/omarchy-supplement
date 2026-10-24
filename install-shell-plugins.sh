#!/bin/bash

set -euo pipefail

# omarchy-shell plugins the reference machine (alienware) runs that are NOT bar
# widgets: overlays and services, enabled through shell.json's `plugins` array
# and never placed on the bar. (Bar widgets are install-bar-plugins.sh's job;
# QuickSwitch has install-quickswitch.sh.)
#
#   omadock                     macOS-style dock (overlay)
#   mihai.spotlight             Spotlight launcher, ALT+SPACE / SUPER+\ (overlay)
#   io.github.qempexe.altscape  ALT+TAB switcher with previews (service + overlay;
#                               it also ships a bar button, which Shibumi has no
#                               slot for -- SUPER+ALT+A opens its settings)
#
# Their Hyprland binds and window rules are in hypr/lua/apps.lua, guarded on
# each plugin being installed -- except Altscape's ALT+TAB, which its own
# `altscape-binds sync` writes at the end of ~/.config/hypr/hyprland.lua.
#
# Settings are seeded from plugin-config/ only when the machine has none, and
# then belong to the plugin: like Strata (see install-strata.sh), each one
# replaces its file on save, so a stowed symlink would be silently turned back
# into a plain file -- and omadock refuses to read a non-regular file at all.
#
# Opt out per plugin with a space-separated list of ids:
#   SHELL_PLUGINS_SKIP="omadock" ./install-shell-plugins.sh

SKIP=" ${SHELL_PLUGINS_SKIP:-} "
skipped() { [[ $SKIP == *" $1 "* ]]; }

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SEEDS="$SCRIPT_DIR/plugin-config"

for d in "$HOME/.local/share/omarchy/bin" /usr/share/omarchy/bin; do
  [ -d "$d" ] && PATH="$d:$PATH"
done
export PATH

if ! command -v omarchy >/dev/null 2>&1 || ! command -v omarchy-shell >/dev/null 2>&1; then
  echo "install-shell-plugins: omarchy / omarchy-shell not on PATH (pre-Quattro Omarchy?); skipping." >&2
  exit 0
fi

PLUGINS_DIR="$HOME/.config/omarchy/plugins"
FAILED=0

seed() {
  local src="$SEEDS/$1" dst="$2"
  [ -e "$dst" ] && return 0
  install -Dm644 "$src" "$dst"
  echo "  Seeded $dst"
}

# Same add-or-update shape as install-quickswitch.sh. A checkout on a local
# branch (the reference machine carried a fix for Altscape that way before
# upstream merged it) makes `update` fail; that is a warning, not a failure.
git_plugin() {
  local id="$1" url="$2"
  if [ -d "$PLUGINS_DIR/$id/.git" ]; then
    omarchy plugin update "$id" --yes || echo "  warning: update of $id failed; keeping the installed version" >&2
  elif [ -e "$PLUGINS_DIR/$id" ]; then
    echo "  $id is installed but not from git; leaving it as is."
  else
    omarchy plugin add "$url" --enable --yes || {
      echo "  warning: could not add $id from $url" >&2
      FAILED=1
      return 1
    }
  fi
  # `enable` takes [placement], not --yes (that would be read as a placement).
  omarchy plugin enable "$id" >/dev/null 2>&1 || true
}

if ! skipped omadock; then
  echo "==> omadock"
  seed omadock.json "$HOME/.config/omarchy/omadock.json"
  git_plugin omadock https://github.com/thepathless/omadock.git || true
fi

# Spotlight ships in a multi-plugin collection repo whose install.sh copies one
# subdirectory into place (not a git checkout, so no `omarchy plugin update`).
# When it is already installed, pass --update so each run re-copies the current
# upstream version -- without it install.sh just skips, and the copy freezes at
# whatever version the machine first got. The plugin keeps no state in its own
# directory, so replacing it wholesale loses nothing. Its own --enable would
# place it in a bar section, which is wrong for an overlay, so it is enabled
# separately.
if ! skipped mihai.spotlight; then
  echo "==> mihai.spotlight"
  update_flag=()
  [ -e "$PLUGINS_DIR/mihai.spotlight" ] && update_flag=(--update)
  tmp="$(mktemp -d)"
  if git clone --quiet --depth 1 https://github.com/nightdevil00/Plugins.git "$tmp/Plugins" &&
    "$tmp/Plugins/install.sh" "${update_flag[@]}" mihai.spotlight; then
    :
  elif ((${#update_flag[@]})); then
    echo "  warning: update of mihai.spotlight failed; keeping the installed version" >&2
  else
    echo "  warning: could not install mihai.spotlight" >&2
    FAILED=1
  fi
  rm -rf "$tmp"
  [ -e "$PLUGINS_DIR/mihai.spotlight" ] && { omarchy plugin enable mihai.spotlight >/dev/null 2>&1 || true; }
fi

if ! skipped io.github.qempexe.altscape; then
  echo "==> io.github.qempexe.altscape"
  seed altscape.json "$HOME/.local/state/omarchy-altscape/settings.json"
  if git_plugin io.github.qempexe.altscape https://github.com/qempexe/omarchy-altscape.git; then
    # Writes (or refreshes) the marked ALT+TAB block in hyprland.lua and reloads
    # Hyprland only if it changed.
    binds="$PLUGINS_DIR/io.github.qempexe.altscape/bin/altscape-binds"
    [ -x "$binds" ] && { "$binds" sync alt >/dev/null || echo "  warning: altscape-binds sync failed" >&2; }
  fi
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

cat <<'EOF'

Shell plugins installed.
  OmaDock     the dock (settings from omadock.json on the reference machine)
  Spotlight   ALT+SPACE or SUPER+\
  Altscape    ALT+TAB; SUPER+ALT+A for its settings
EOF

exit "$FAILED"
