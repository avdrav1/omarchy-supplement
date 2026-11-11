#!/bin/bash
# Third-party bar widgets (manifest/bar-widgets.txt), their backends, and settings from dotfiles
source "$(dirname "$0")/../lib/common.sh"

# On the Shibumi bar, `omarchy plugin enable <id> <section>` only decides that a
# widget is loaded; Shibumi's reconciler then auto-places it in a free v2Layout
# slot. When the slots run out the widget stays installed but unplaced (the
# Control Center reports it as plugin-capacity feedback) -- expected, not a failure.

SKIP=" ${BAR_WIDGETS_SKIP:-} "
skipped() { [[ $SKIP == *" $1 "* ]]; }
FAILED=0

in_bar_layout() {
  jq -e --arg id "$1" '[.bar.layout // {} | .[] | .[]? | .id] | index($id) != null' "$SHELL_JSON" >/dev/null 2>&1
}

# Place a widget only when it isn't on the bar yet: `enable` with a section
# MOVES the widget, so doing it every run would reshuffle the bar.
place() {
  in_bar_layout "$1" && return 0
  omarchy plugin enable "$1" "$2" || { warn "could not enable $1"; FAILED=1; }
}

# Local fixes in config/plugins/patches/<id>/*.patch. They dirty the checkout,
# and `omarchy plugin update` won't fast-forward a dirty checkout, so each patch
# is reverted before an update and re-applied after. Once upstream merges the
# fix, the patch stops applying forward and this goes quiet.
patches() {
  local id="$1" action="$2" dir="$PLUGINS_DIR/$1" p
  [ -d "$CONFIG/plugins/patches/$id" ] && [ -d "$dir/.git" ] || return 0
  for p in "$CONFIG/plugins/patches/$id"/*.patch; do
    case "$action" in
    revert)
      [ -n "$(git -C "$dir" status --porcelain)" ] && git -C "$dir" apply -R --check "$p" 2>/dev/null &&
        git -C "$dir" apply -R "$p"
      ;;
    apply)
      if git -C "$dir" apply --check "$p" 2>/dev/null; then
        git -C "$dir" apply "$p" && note "applied $(basename "$p")"
      elif ! git -C "$dir" apply -R --check "$p" 2>/dev/null; then
        warn "$(basename "$p") no longer applies to $id; left stock"
      fi
      ;;
    esac
  done
  return 0
}

# Widget settings from the dotfiles `omarchy-plugins` package (one JSON object
# per widget id), written onto the widget's bar entry on every run -- dotfiles
# is the source of truth, so copy changes made in a widget's UI back there.
# Only changed keys are written; each write reloads the shell (~3s here), hence
# the longer IPC timeout.
SETTINGS_DIR="$HOME/.config/omarchy/plugin-settings"
apply_settings() {
  local id="$1" file="$SETTINGS_DIR/$1.json" key want have
  [ -f "$file" ] || return 0
  in_bar_layout "$id" || { note "$id is not on the bar; its dotfiles settings were not applied"; return 0; }
  while IFS= read -r key; do
    want=$(jq -c --arg k "$key" '.[$k]' "$file")
    have=$(jq -c --arg id "$id" --arg k "$key" '[.bar.layout // {} | .[] | .[]? | objects | select(.id == $id)][0][$k]' "$SHELL_JSON")
    [ "$want" = "$have" ] && continue
    OMARCHY_SHELL_IPC_TIMEOUT="${OMARCHY_SHELL_IPC_TIMEOUT:-15s}" omarchy bar set "$id" "$key" "$want" --json >/dev/null ||
      { warn "could not set $key on $id"; FAILED=1; }
  done < <(jq -r 'keys[]' "$file")
}

git_widget() {
  local id="$1" url="$2" section="$3"
  step "$id"
  if [ -d "$PLUGINS_DIR/$id/.git" ]; then
    patches "$id" revert
    omarchy plugin update "$id" --yes || warn "update of $id failed; keeping the installed version"
    patches "$id" apply
  elif [ -e "$PLUGINS_DIR/$id" ]; then
    note "installed but not from git; leaving it as is"
  else
    omarchy plugin add "$url" --yes || { warn "could not add $id"; FAILED=1; return 0; }
    patches "$id" apply
  fi
  place "$id" "$section"
  apply_settings "$id"
}

# ── Backends ─────────────────────────────────────────────────────────────────
# The widgets can install these from their own panels, but one pkexec prompt at
# a time; doing it here keeps a fresh bar from being full of "install me" buttons.
step "Widget backends"
backends=()
skipped aweiward.omaqbt || backends+=(qbittorrent-nox)
skipped ayan.nordvpn || backends+=(nordvpn-bin)
skipped local.omastat || backends+=(rust)
pkg "${backends[@]}"
if ! skipped ayan.nordvpn; then
  system_service nordvpnd.service
  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx nordvpn; then
    sudo usermod -aG nordvpn "$USER"
    note "added $USER to the nordvpn group (takes effect at next login)"
  fi
fi

# ytmusic-plus replaces its settings.json with mv on every save, so it is seeded
# rather than stowed -- and before the widget is added, so it starts with ours.
skipped local.ytmusic-plus ||
  seed "$CONFIG/plugins/seeds/ytmusic-plus.json" "$HOME/.local/share/omarchy-ytmusic-plus/settings.json"

# ── Widgets ──────────────────────────────────────────────────────────────────
while read -r id url section; do
  skipped "$id" && { note "$id skipped"; continue; }
  git_widget "$id" "$url" "$section"
done < <(manifest bar-widgets.txt)

# omaqbt's daemon unit is written by its own helper (what the panel's "Start
# daemon" button runs); it also turns on qBittorrent's localhost Web UI.
if ! skipped aweiward.omaqbt && [ -x "$PLUGINS_DIR/aweiward.omaqbt/qbt" ] &&
  ! systemctl --user is-enabled omaqbt-nox.service &>/dev/null; then
  "$PLUGINS_DIR/aweiward.omaqbt/qbt" start-daemon || warn "could not start the omaqbt daemon"
fi

# ── Omastat (source build) ───────────────────────────────────────────────────
# The widget needs the omastatd daemon, which ships only as Rust source; its
# install.sh builds it with cargo (minutes), installs the user service, and
# copies the widget in as local.omastat. Skipped when already at the pinned version.
#
# PINNED: v0.2.0 renamed the project to Nagori (new plugin id, daemon, service
# and data dir, no migration), so moving to it is a deliberate switch, not a
# version bump. OMASTAT_REF overrides.
if ! skipped local.omastat; then
  step "local.omastat"
  OMASTAT_SRC="$HOME/Omastat"
  OMASTAT_REF="${OMASTAT_REF:-v0.1.6}"
  if [ -d "$OMASTAT_SRC/.git" ]; then
    git -C "$OMASTAT_SRC" fetch --tags --quiet || true
  else
    git clone --quiet https://github.com/ThisIsRinesi/Omastat.git "$OMASTAT_SRC"
  fi
  want=$(git -C "$OMASTAT_SRC" show "$OMASTAT_REF:manifest.json" 2>/dev/null | jq -r .version 2>/dev/null || true)
  have=$(jq -r .version "$PLUGINS_DIR/local.omastat/manifest.json" 2>/dev/null || true)
  if [ -n "$want" ] && [ "$want" = "$have" ] && [ -x "$HOME/.cargo/bin/omastatd" ]; then
    :
  elif git -C "$OMASTAT_SRC" -c advice.detachedHead=false checkout --quiet "$OMASTAT_REF"; then
    note "building Omastat ${want:-?} with cargo (takes a few minutes)"
    (cd "$OMASTAT_SRC" && ./install.sh) || { warn "Omastat install failed"; FAILED=1; }
  else
    warn "could not check out Omastat $OMASTAT_REF"
    FAILED=1
  fi
  place local.omastat right
fi

shell_rescan
exit "$FAILED"
