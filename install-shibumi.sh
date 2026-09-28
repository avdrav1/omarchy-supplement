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
# Keep a persistent clone: `shibumi-suite update` re-runs from it, and the
# plugin payloads it stages live here too.
#
# Always install the LATEST RELEASE TAG, never `main` -- including on a fresh
# clone or a checkout still on a branch. Upstream: "Do not install or update
# from main." Each release only updates from a whitelist of release identities,
# so an install staged from an untagged main commit is rejected by every later
# update/repair/uninstall. versionsort.suffix=- ranks a final vX.Y.Z above its
# vX.Y.Z-beta.N prereleases.
if [ -d "$SRC_DIR/.git" ]; then
  echo "Fetching Shibumi-Shell releases into $SRC_DIR..."
  git -C "$SRC_DIR" fetch --tags --force --quiet origin
else
  echo "Cloning Shibumi-Shell into $SRC_DIR..."
  git clone "$REPO_URL" "$SRC_DIR"
fi
latest_tag="$(git -C "$SRC_DIR" -c versionsort.suffix=- tag -l 'v*' --sort=-v:refname | head -n1)"
if [ -z "$latest_tag" ]; then
  echo "ERROR: no release tags found in $SRC_DIR." >&2
  exit 1
fi
latest_rev="$(git -C "$SRC_DIR" rev-parse "$latest_tag^{commit}")"
echo "Checking out Shibumi $latest_tag..."
git -C "$SRC_DIR" checkout --quiet --detach "$latest_tag"

SUITE="$SRC_DIR/scripts/shibumi-suite"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/shibumi"

# ── Recover an install too old to update ─────────────────────────────────────
# Each suite release only updates from a fixed list of predecessor identities
# (currently beta.11 and later). An older install -- e.g. a machine last set up
# at v0.1.1-beta.7 -- makes `update` refuse with "installed identity is
# unsupported" and change nothing, so this installer could never move it on.
#
# Upstream's documented fix (docs/install.md, "Supervised recovery"): uninstall
# with the *exact* old revision recorded in install.json, keeping settings, then
# install the current release. The old code runs from a throwaway worktree so
# the main checkout stays where it is. Only the recorded revision is ever used
# -- if it isn't a known commit we stop rather than guess.
if { "$SUITE" status 2>&1 || true; } | grep -q 'installed identity is unsupported'; then
  old_rev="$(jq -r '.sourceRevision // empty' "$STATE_DIR/install.json" 2>/dev/null || true)"
  if [ -z "$old_rev" ] || ! git -C "$SRC_DIR" cat-file -e "$old_rev^{commit}" 2>/dev/null; then
    echo "ERROR: Shibumi install is too old to update, and its recorded source" >&2
    echo "revision (${old_rev:-none}) is not a commit in $SRC_DIR." >&2
    echo "See 'Supervised recovery' in $SRC_DIR/docs/install.md." >&2
    exit 1
  fi
  echo "Shibumi install ($(git -C "$SRC_DIR" describe --tags --always "$old_rev")) is too old to update;"
  echo "uninstalling it with its own code (settings kept) before reinstalling..."

  backup="$HOME/shibumi-backup-$(date +%s)"
  mkdir -p "$backup"
  cp -a "$HOME/.config/omarchy/shell.json" "$STATE_DIR" "$backup/"
  echo "  Backed up shell.json and suite state to $backup"

  old_tree="$(mktemp -d)"
  trap 'git -C "$SRC_DIR" worktree remove --force "$old_tree" 2>/dev/null; rm -rf "$old_tree"' EXIT
  git -C "$SRC_DIR" worktree add --quiet --detach "$old_tree" "$old_rev"
  "$old_tree/scripts/shibumi-suite" uninstall --keep-settings --yes
  git -C "$SRC_DIR" worktree remove --force "$old_tree"
  trap - EXIT
fi

# ── Install or update the suite ──────────────────────────────────────────────
# `install` is the first-run path; once installed, upstream's re-run path is
# `update` (running `install` again errors with "already suite-managed"). Detect
# which via `status`, whose line reads "Install state: not installed" before the
# first install and "Install state: <version> (<hash>)" afterwards. (Captured
# rather than piped: under pipefail a non-zero `status` exit would mask the
# match and send a fresh machine down the update path.)
#
# Best-effort (|| true): after staging plugins to disk the suite also live-
# rescans the running shell, which returns non-zero when omarchy-shell happens
# to be down. The plugins are staged regardless and we restart the shell below,
# so don't let that abort us -- the end-state check further down is the real
# gate.
#
# Personal settings: Shibumi keeps them in ~/.config/omarchy/shell.json, which
# neither this repo nor the dotfiles track, so a fresh install comes up with
# defaults. shibumi/settings.json is the tracked copy (capture it with
# ./save-shibumi-settings.sh):
#   state      -> the State plugin entry's `shibumi` object (layout, widgets,
#                 presentation, picker, workspace mode...)
#   barWidgets -> non-Shibumi widgets (e.g. omarchy.keyboard-layout) appended
#                 to each bar section if not already there
# Applied only on a first install, so re-runs never clobber control-center
# changes that haven't been saved back yet.
SETTINGS_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/shibumi/settings.json"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
apply_settings() {
  [ -f "$SETTINGS_FILE" ] || return 0
  echo "Applying saved Shibumi settings from $SETTINGS_FILE..."
  local tmp
  tmp="$(mktemp)"
  jq --slurpfile saved "$SETTINGS_FILE" '
    $saved[0] as $s
    | (.plugins[] | select(.id == "hancore.shibumi.state") | .shibumi) = $s.state
    | reduce ($s.barWidgets // {} | to_entries[]) as $sec (.;
        reduce $sec.value[] as $w (.;
          if any(.bar.layout[$sec.key][]?; .id == $w.id) then .
          else .bar.layout[$sec.key] += [$w] end))
  ' "$SHELL_JSON" >"$tmp"
  # cat (not mv) keeps shell.json's inode and 0600 mode.
  cat "$tmp" >"$SHELL_JSON"
  rm -f "$tmp"
}

suite_status="$("$SUITE" status 2>&1 || true)"
if printf '%s\n' "$suite_status" | grep -q 'Install state: not installed'; then
  echo "Installing Shibumi suite (24 plugins)..."
  "$SUITE" install --yes || true
  apply_settings
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
if ! printf '%s\n' "$status" | grep -q "^Install state: .*($latest_rev)"; then
  echo "ERROR: Shibumi is installed but not at $latest_tag ($latest_rev). Suite status:" >&2
  printf '%s\n' "$status" >&2
  exit 1
fi

echo "Shibumi Shell $latest_tag installed. Re-run this script to update to the latest release."
