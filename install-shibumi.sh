#!/bin/bash

set -euo pipefail

# Install Shibumi Shell -- HANCORE-linux's native bar and plugin suite for
# Omarchy Quattro -- from source, and retire the older Quickshell Rise bar it
# supersedes.
#   Upstream: https://github.com/HANCORE-linux/Shibumi-Shell
#
# Unlike Rise (a standalone `qs` instance launched by an Omarchy post-boot hook
# from ~/.config/quickshell/bar), Shibumi installs as ~24 Omarchy plugins under
# ~/.config/omarchy/plugins and edits ~/.config/omarchy/shell.json, so it runs
# *inside* the stock omarchy-shell process rather than alongside it. Its own
# `shibumi-suite` CLI does that transactionally (and is reversible via
# `shibumi-suite uninstall`); this script only wraps it with the package,
# clone, and Rise-teardown steps upstream leaves to the user.
#
# Requires Omarchy Quattro (Omarchy 4) and Quickshell 0.3.0+. The suite itself
# refuses to run on anything else, so we don't re-check here.

SRC_DIR="$HOME/.local/share/Shibumi-Shell"
REPO_URL="https://github.com/HANCORE-linux/Shibumi-Shell.git"

# ── Runtime dependencies ─────────────────────────────────────────────────────
# The suite installs no packages itself; these are the runtime commands and
# fonts its widgets shell out to. Install only what's missing so a re-run on a
# provisioned machine never reaches for sudo (and can't fail non-interactively)
# -- the same pattern the other installers here use.
deps=(
  python jq curl networkmanager power-profiles-daemon upower xdg-utils
  libnotify wl-clipboard ttf-material-symbols-variable
  ttf-jetbrains-mono-nerd-basic noto-fonts-cjk adwaita-fonts
)
missing=()
for pkg in "${deps[@]}"; do
  pacman -Qq "$pkg" &>/dev/null || missing+=("$pkg")
done
if ((${#missing[@]})); then
  sudo pacman -S --noconfirm --needed "${missing[@]}"
fi

# ── Source checkout ──────────────────────────────────────────────────────────
# Keep a persistent clone: `shibumi-suite update` re-runs from it after a
# `git pull`, and the plugin payloads it stages live here too.
if [ -d "$SRC_DIR/.git" ]; then
  echo "Updating Shibumi-Shell checkout in $SRC_DIR..."
  git -C "$SRC_DIR" pull --ff-only
else
  echo "Cloning Shibumi-Shell into $SRC_DIR..."
  git clone "$REPO_URL" "$SRC_DIR"
fi

SUITE="$SRC_DIR/scripts/shibumi-suite"

# ── Install or update the suite ──────────────────────────────────────────────
# `install` is the first-run path; once installed, upstream's re-run path is
# `update` (running `install` again errors with "already suite-managed"). Detect
# which via `status`, whose line reads "Install state: not installed" before the
# first install and "Install state: <version> (<hash>)" afterwards.
#
# Best-effort (|| true): after staging plugins to disk the suite also live-
# rescans the running shell, which returns non-zero when omarchy-shell happens
# to be down. The plugins are staged regardless and we restart the shell below,
# so don't let that abort us -- the end-state check further down is the real
# gate.
if "$SUITE" status 2>/dev/null | grep -q 'Install state: not installed'; then
  echo "Installing Shibumi suite (24 plugins)..."
  "$SUITE" install --yes || true
else
  echo "Shibumi already installed; updating plugin set..."
  "$SUITE" update --yes || true
fi

# ── Retire the Quickshell Rise bar ───────────────────────────────────────────
# Rise ran as a separate `qs` instance and left an Omarchy post-boot launcher,
# a theme-set hook, helper binaries, and systemd user units behind. Left in
# place it would keep drawing its own bar over Shibumi's, so tear the whole
# footprint down. Every step is guarded/idempotent and non-fatal: on a machine
# that never had Rise (or where a prior run already removed it) this is a no-op.
echo "Retiring the Quickshell Rise bar (superseded by Shibumi)..."

# 1. Stop the live Rise bar and its update-check units.
for unit in $(systemctl --user list-units --no-legend 'qsrise-bar-*' 2>/dev/null | awk '{print $1}'); do
  systemctl --user stop "$unit" 2>/dev/null || true
done
systemctl --user disable --now qs-shell-update-check.timer 2>/dev/null || true
systemctl --user stop qs-shell-update-check.service 2>/dev/null || true
# Rise's config path (~/.config/quickshell/bar/shell.qml) appears only in
# Quickshell's *instance registry*, never in the process cmdline -- a Rise
# process reads `qs -n -d -c bar`, so matching the path with `pkill -f` is a
# silent no-op that leaves the old bar drawing over Shibumi. Ask Quickshell
# instead, and kill by pid so the stock omarchy-shell instance (config path
# /usr/share/omarchy/shell/shell.qml) is never caught.
if command -v qs >/dev/null 2>&1; then
  for pid in $(qs list --all 2>/dev/null | awk -v dir="$HOME/.config/quickshell/bar/" '
        /^[[:space:]]*Process ID:/  { pid = $3 }
        /^[[:space:]]*Config path:/ { if (index($3, dir) == 1) print pid }'); do
    qs kill --pid "$pid" >/dev/null 2>&1 || kill "$pid" 2>/dev/null || true
  done
fi

# 2. Remove the Omarchy hooks that relaunch/refresh Rise on boot and theme-set.
rm -f "$HOME/.config/omarchy/hooks/post-boot.d/quickshell-rise"
rm -f "$HOME/.config/omarchy/hooks/theme-set.d/50-quickshell-bar.sh"

# 3. Remove Rise's config, helper binaries, systemd unit files, and state.
rm -rf "$HOME/.config/quickshell/bar" "$HOME/.config/quickshell/bin"
rm -f  "$HOME/.config/systemd/user/qs-shell-update-check.service" \
       "$HOME/.config/systemd/user/qs-shell-update-check.timer"
rm -rf "$HOME/.local/state/quickshell-rise"
systemctl --user daemon-reload 2>/dev/null || true
# NOTE: the *-usage.service units (claude/codex/opencode) are left alone -- they
# are generic usage collectors that feed a Quickshell quota widget, and
# Shibumi's hancore.shibumi.ai plugin consumes the same data.

# ── Show Shibumi on the stock bar ────────────────────────────────────────────
# Rise had hidden the stock omarchy bar so its own bar could own the slot.
# Shibumi renders *through* that stock bar, so show it and reload the shell to
# pick up the freshly staged plugins. Guarded on an active Hyprland session; the
# toggle/reload are no-ops otherwise.
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  # Omarchy's bin dir is not guaranteed on PATH in a non-interactive run; if the
  # omarchy-* commands aren't found the steps below would silently no-op and the
  # bar would stay hidden. Put it on PATH first.
  for d in "$HOME/.local/share/omarchy/bin" /usr/share/omarchy/bin; do
    [ -d "$d" ] && PATH="$d:$PATH"
  done
  export PATH
  # INVERTED FLAG: omarchy tracks bar visibility as a `bar-off` toggle, so
  # `omarchy-toggle-bar off` SHOWS the bar (clears bar-off) and `on` hides it.
  omarchy-toggle-bar off >/dev/null 2>&1 || omarchy toggle bar off >/dev/null 2>&1 || true
  omarchy-restart-shell  >/dev/null 2>&1 || omarchy restart shell >/dev/null 2>&1 || true
fi

# ── Verify ───────────────────────────────────────────────────────────────────
# The staging calls above are best-effort, so confirm the suite actually reports
# itself installed with Shibumi as the configured bar before declaring success.
status="$("$SUITE" status 2>/dev/null || true)"
if ! printf '%s\n' "$status" | grep -q 'Managed plugins:' \
   || ! printf '%s\n' "$status" | grep -q 'Configured bar: hancore.shibumi'; then
  echo "ERROR: Shibumi did not finish installing cleanly. Suite status:" >&2
  printf '%s\n' "$status" >&2
  exit 1
fi

echo "Shibumi Shell installed. Update later with:"
echo "  git -C \"$SRC_DIR\" pull --ff-only && \"$SUITE\" update --yes"
