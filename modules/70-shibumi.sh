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

# `update` keeps whichever bar is active, and Shibumi's own bar switcher (or
# `shibumi-suite deactivate`) can leave the stock omarchy.bar configured.
# Shibumi is the bar on these machines, so switch back.
if ! "$SUITE" status 2>/dev/null | grep -q 'Configured bar: hancore.shibumi'; then
  echo "Stock bar is active; activating Shibumi..."
  "$SUITE" activate --yes || true
fi

# ── Shibumi switcher ─────────────────────────────────────────────────────────
# Our own Alt+Tab overlay (config/shell-plugins/av.shibumi-switcher), kept out
# of the suite's hancore.shibumi.* namespace so suite updates never touch it.
# A third-party plugin is enabled by having an entry in shell.json's plugins[].
# The Alt+Tab binds in config/hypr/bindings.lua switch over once it's here.
SWITCHER_ID="av.shibumi-switcher"
SWITCHER_SRC="$CONFIG/shell-plugins/$SWITCHER_ID"
while IFS= read -r -d '' f; do
  put "$PLUGINS_DIR/$SWITCHER_ID/${f#"$SWITCHER_SRC"/}" <"$f"
done < <(find "$SWITCHER_SRC" -type f -print0)
enable_plugin() {
  jq -e --arg id "$1" 'any(.plugins[]?; .id == $id)' "$SHELL_JSON" >/dev/null && return 0
  local tmp
  tmp="$(mktemp)"
  jq --arg id "$1" '.plugins += [{id: $id}]' "$SHELL_JSON" >"$tmp"
  cat "$tmp" >"$SHELL_JSON"
  rm -f "$tmp"
  note "enabled $1"
}
enable_plugin "$SWITCHER_ID"

# ── Spotlight ────────────────────────────────────────────────────────────────
# mihai's Spotlight launcher (ALT+SPACE / SUPER+\ / ALT+\, binds in
# config/hypr/bindings.lua). It lives in a multi-plugin repo, so only its
# directory is copied out. Installed once and not auto-updated: it runs
# commands inside the shell, so read a new version before replacing it
# (rm -r the plugin dir and re-run this module to take the latest).
SPOTLIGHT_ID="mihai.spotlight"
if [ ! -e "$PLUGINS_DIR/$SPOTLIGHT_ID" ]; then
  tmp="$(mktemp -d)"
  if git clone --quiet --depth 1 https://github.com/nightdevil00/Plugins.git "$tmp/Plugins" &&
    [ -f "$tmp/Plugins/$SPOTLIGHT_ID/manifest.json" ]; then
    cp -a "$tmp/Plugins/$SPOTLIGHT_ID" "$PLUGINS_DIR/$SPOTLIGHT_ID"
    note "installed $SPOTLIGHT_ID ($(git -C "$tmp/Plugins" rev-parse --short HEAD))"
  else
    warn "could not install $SPOTLIGHT_ID"
  fi
  rm -rf "$tmp"
fi
[ -e "$PLUGINS_DIR/$SPOTLIGHT_ID" ] && enable_plugin "$SPOTLIGHT_ID"
in_session && hyprctl reload >/dev/null 2>&1 || true

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
