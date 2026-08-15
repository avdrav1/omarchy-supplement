#!/bin/bash

# Install hyprland-scroll-overview: a workspace overview for Hyprland driven by
# touchpad scroll (hyprpm plugin "scrolloverview", by yayuuu).
# Upstream: https://github.com/yayuuu/hyprland-scroll-overview
#
# This is an hyprpm plugin, NOT a pacman/AUR package. hyprpm compiles it against
# the Hyprland headers of the *currently installed* Hyprland, so the build is
# version-locked: after every Hyprland upgrade the plugin silently stops loading
# until `hyprpm update` rebuilds it. hypr/hyprpm-plugins.hook (installed below)
# prints a reminder after any Hyprland upgrade.
#
# Hyprland wiring (the plugin config, the SUPER+grave bind, the scrolloverview
# submap and the ALT+1..9 submap_universal binds) is applied by
# install-hyprland-overrides.sh, from hypr/lua/scrolloverview.lua on Lua
# machines or hyprland-overrides.conf on hyprlang ones. Nothing for this plugin
# ships via the dotfiles repo -- it has no user config file outside Hyprland's.
#
# Under the Lua parser the plugin is reached through its Lua namespace
# (hl.plugin.scrolloverview.*), NOT the scrolloverview:* hyprlang dispatchers --
# those are unreachable from a Lua config. The Lua module no-ops when the plugin
# isn't built, so a missing/stale build is silent rather than an error; run this
# script (and `hyprctl reload`) to bring it back.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_REPO="https://github.com/yayuuu/hyprland-scroll-overview"
PLUGIN_NAME="scrolloverview"
PLUGIN_FALLBACK_REV="main"

if ! command -v hyprpm >/dev/null 2>&1; then
  echo "hyprpm not found (ships with Hyprland). Install Hyprland first."
  exit 1
fi

# hyprpm needs the toolchain to compile the plugin against Hyprland's headers.
# Only install what's missing so a re-run on a provisioned machine doesn't reach
# for sudo (and doesn't fail in a non-interactive run) just to reconfirm it.
# base-devel is a group -- `pacman -Qq base-devel` fails even when every member
# is installed -- so probe the compiler directly as a proxy for its presence.
toolchain_missing=()
{ command -v gcc && command -v make; } &>/dev/null || toolchain_missing+=(base-devel)
for pkg in cmake meson ninja cpio git; do
  pacman -Qq "$pkg" &>/dev/null || toolchain_missing+=("$pkg")
done
if ((${#toolchain_missing[@]})); then
  sudo pacman -S --noconfirm --needed "${toolchain_missing[@]}"
fi

# Post-upgrade reminder hook, mirroring quickshell/quickshell-check.hook.
# It only notifies: the rebuild needs an interactive sudo, which a pacman hook
# has no tty for.
#
# Installed BEFORE the hyprpm steps deliberately. Under `set -e` any hyprpm
# failure aborts the script, and this hook is pure documentation with no
# dependency on the build succeeding -- installing it afterwards meant a failed
# run left no reminder behind on top of leaving no plugin.
# Install/refresh the hook only when it differs from what's already there, so a
# re-run doesn't spend a sudo just to overwrite an identical file. The hooks dir
# is world-readable, so the cmp needs no privileges.
HOOK_SRC="$SCRIPT_DIR/hypr/hyprpm-plugins.hook"
HOOK_DST="/etc/pacman.d/hooks/hyprpm-plugins.hook"
if ! cmp -s "$HOOK_SRC" "$HOOK_DST" 2>/dev/null; then
  echo "Installing pacman hook for post-upgrade plugin checks..."
  sudo mkdir -p /etc/pacman.d/hooks
  sudo cp "$HOOK_SRC" "$HOOK_DST"
fi

# NOTE: hyprpm elevates itself via sudo to write its state under
# /var/cache/hyprpm/$USER (root-owned), so the calls below may prompt for a
# password. That is also why this step cannot be automated from a pacman hook.

# Refresh the Hyprland headers before anything else. hyprpm builds against the
# headers it cached for the Hyprland it saw last, and every `hyprpm` subcommand
# -- `add` included -- refuses to run with "Headers outdated, please run hyprpm
# update" once the compositor has been upgraded past them. Doing this only in
# the already-added branch below left a machine whose state.toml lost its
# [repos] section (populated headersRoot/, empty `hyprpm list`) permanently
# stuck: `add` died on stale headers, and so did the fallback, because the
# header check fires before the commit-pin logic ever runs.
hyprpm update

# `hyprpm add` is not re-runnable -- it errors if the repo is already present --
# so guard on the plugin already being known to hyprpm.
if hyprpm list 2>/dev/null | grep -q "$PLUGIN_NAME"; then
  echo "Plugin $PLUGIN_NAME already added; rebuilt by the update above."
else
  # hyprpm refuses to add a plugin when upstream's hyprpm.toml carries no commit
  # pin for the running Hyprland. It bails *before* cloning, so no plugin source
  # and no .so are produced -- the only trace is a populated headersRoot/ and a
  # state.toml with no [repos] section. Arch ships Hyprland releases faster than
  # upstream adds pins, so this is the normal case here rather than an edge one
  # (e.g. 0.55.4, where upstream's pins stopped at 0.55.3).
  #
  # Passing an explicit git rev makes hyprpm ignore commit locks and build that
  # revision instead. The plugin may genuinely not compile against a newer
  # Hyprland, in which case this fails loudly at the build step -- which is the
  # informative failure, unlike the silent one above.
  hyprpm add "$PLUGIN_REPO" || {
    echo "No commit pin for the running Hyprland; retrying against $PLUGIN_FALLBACK_REV."
    hyprpm add "$PLUGIN_REPO" "$PLUGIN_FALLBACK_REV"
  }
fi

hyprpm enable "$PLUGIN_NAME"

# Load the plugin into the running compositor. Without this the dispatchers
# (scrolloverview:overview etc.) don't exist yet and `hyprctl configerrors`
# reports "Invalid dispatcher" for every bind until the next login.
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  hyprpm reload -n
fi

echo "hyprland-scroll-overview installation complete."
echo "Toggle the overview with SUPER+\` (grave)."
