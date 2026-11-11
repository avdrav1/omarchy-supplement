#!/bin/bash
# Shibumi Shell bar and plugin suite, built from the latest release tag
source "$(dirname "$0")/../lib/common.sh"

# Shibumi Shell -- HANCORE-linux's bar and plugin suite for Omarchy 4.
#   Upstream: https://github.com/HANCORE-linux/Shibumi-Shell
#
# Shibumi installs as ~24 Omarchy plugins under ~/.config/omarchy/plugins and
# edits ~/.config/omarchy/shell.json, so it runs inside the stock omarchy-shell.
# Its own `shibumi-suite` CLI does that transactionally (and is reversible via
# `shibumi-suite uninstall`); this module wraps it with the dependencies, the
# source checkout, and the saved settings.
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
pkg "${deps[@]}"

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

# ── Preflight: a working omarchy-shell ───────────────────────────────────────
# Every suite transaction below talks to the running omarchy-shell. If quickshell
# can't even start, they fail partway and leave an interrupted transaction --
# which is how a machine got stuck on beta.7: a qt6-base upgrade broke an
# AUR-built quickshell (`symbol lookup error ... Qt_6_PRIVATE_API`), and the
# recovery below died mid-uninstall with no shell to talk to. Stop before
# touching anything instead.
#
# LD_BIND_NOW resolves every symbol at load, so a Qt ABI mismatch fails even a
# bare --version rather than only once the shell reaches the missing symbol.
if ! qs_err="$(LD_BIND_NOW=1 quickshell --version 2>&1 >/dev/null)"; then
  echo "ERROR: quickshell cannot start, so Shibumi can't be installed or updated:" >&2
  printf '  %s\n' "${qs_err:-quickshell not found}" >&2
  echo "Usually quickshell was built against an older Qt. Run 'omarchy update'" >&2
  echo "(its migrations swap in the repo quickshell), check the bar is back, then" >&2
  echo "re-run this script. Nothing was changed." >&2
  exit 1
fi
# In a desktop session the shell must also be running. It may just have given up
# after crash-looping, so try one restart before failing. (Outside Hyprland there
# is no shell to reach; the suite reports that itself.)
shell_running() { pgrep -f '^(/usr/bin/)?quickshell .*-p /usr/share/omarchy/shell' >/dev/null; }
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && ! shell_running; then
  echo "omarchy-shell is not running; restarting it..."
  omarchy-restart-shell >/dev/null 2>&1 || omarchy restart shell >/dev/null 2>&1 || true
  for _ in {1..10}; do shell_running && break; sleep 1; done
  if ! shell_running; then
    echo "ERROR: omarchy-shell is not running and would not start." >&2
    echo "Check 'journalctl --user -b | grep omarchy-shell', fix it, then re-run." >&2
    echo "Nothing was changed." >&2
    exit 1
  fi
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
# defaults. config/shibumi/settings.json is the tracked copy (capture it with
# tools/save-shibumi-settings.sh):
#   state      -> the State plugin entry's `shibumi` object (layout, widgets,
#                 presentation, picker, workspace mode...)
#   barWidgets -> non-Shibumi widgets (e.g. omarchy.keyboard-layout) appended
#                 to each bar section if not already there
# Applied only on a first install, so re-runs never clobber control-center
# changes that haven't been saved back yet.
SETTINGS_FILE="$CONFIG/shibumi/settings.json"
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

# ── Startup IPC fix ──────────────────────────────────────────────────────────
# Current Omarchy split the shell's `rescanPlugins` IPC (registry only) from
# `reloadPlugins` (rebuilds the bar). Shibumi (through v0.2.1) still calls
# rescanPlugins at startup and waits for a bar that never comes: no bar, no
# error, just `"phase":"timed-out"` in the journal. Point it at reloadPlugins
# when the shell has it. Every suite install/update restores the stock file,
# so this runs each time.
RUNTIME_QML="$PLUGINS_DIR/hancore.shibumi.state/runtime/Runtime.qml"
if grep -q 'function reloadPlugins' /usr/share/omarchy/shell/shell.qml 2>/dev/null &&
  grep -q '"shell", "rescanPlugins"' "$RUNTIME_QML" 2>/dev/null; then
  sed -i 's/"shell", "rescanPlugins"/"shell", "reloadPlugins"/' "$RUNTIME_QML"
  note "patched Shibumi's startup call to reloadPlugins"
fi

# ── Show Shibumi on the stock bar ────────────────────────────────────────────
# Shibumi renders *through* the stock bar, so make sure it is shown, and reload
# the shell to pick up the freshly staged plugins.
if in_session; then
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

echo "Shibumi Shell $latest_tag installed. Run ./setup shibumi to update to the latest release."
