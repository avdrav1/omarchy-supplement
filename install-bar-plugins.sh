#!/bin/bash

set -euo pipefail

# Third-party omarchy-shell bar widgets the reference machine (alienware) runs
# that no other installer here puts in place, plus the stock optional widgets it
# has turned on. The Shibumi suite, the Calendar Sync clock (+ av.weather /
# av.system-update clones), BlueFerry, QuickSwitch and the patched menu each have
# their own installer; this one covers everything else on the bar.
#
# Placement: a widget is placed (`omarchy plugin enable <id> <section>`) ONLY
# when it is not in shell.json's bar.layout yet. `enable` with a section *moves*
# the widget, so calling it unconditionally would shuffle a machine's bar on
# every re-run. Once placed, where it sits is that machine's business.
#
# On the Shibumi bar, bar.layout is not the whole story: the reconciler then
# auto-places each new third-party widget into a free v2Layout slot (see the
# header of install-sync-calendar.sh). When the slots run out, a widget stays
# installed and enabled but unplaced -- the Control Center reports that as
# plugin-capacity feedback. That is the reference machine's state for omamail
# and omaspotify too, so it is expected, not a failure.
#
# Opt out per widget with a space-separated list of ids:
#   BAR_PLUGINS_SKIP="ayan.nordvpn aweiward.omaqbt" ./install-bar-plugins.sh

SKIP=" ${BAR_PLUGINS_SKIP:-} "
skipped() { [[ $SKIP == *" $1 "* ]]; }

for d in "$HOME/.local/share/omarchy/bin" /usr/share/omarchy/bin; do
  [ -d "$d" ] && PATH="$d:$PATH"
done
export PATH

if ! command -v omarchy >/dev/null 2>&1 || ! command -v omarchy-shell >/dev/null 2>&1; then
  echo "install-bar-plugins: omarchy / omarchy-shell not on PATH (pre-Quattro Omarchy?); skipping." >&2
  exit 0
fi

SHELL_JSON="$HOME/.config/omarchy/shell.json"
PLUGINS_DIR="$HOME/.config/omarchy/plugins"
FAILED=0

in_bar_layout() {
  jq -e --arg id "$1" \
    '[.bar.layout // {} | .[] | .[]? | .id] | index($id) != null' \
    "$SHELL_JSON" >/dev/null 2>&1
}

place() {
  local id="$1" section="$2"
  if in_bar_layout "$id"; then
    echo "  $id already on the bar; leaving its placement alone."
  else
    omarchy plugin enable "$id" "$section" || {
      echo "  warning: could not enable $id" >&2
      FAILED=1
    }
  fi
}

# add-or-update from git, then place. Mirrors install-quickswitch.sh: a git
# checkout is fast-forwarded with `omarchy plugin update`, anything else is
# added fresh. `add` runs WITHOUT --enable -- placement is place()'s job.
git_plugin() {
  local id="$1" url="$2" section="$3"
  if skipped "$id"; then
    echo "==> $id: skipped (BAR_PLUGINS_SKIP)"
    return
  fi
  echo "==> $id"
  if [ -d "$PLUGINS_DIR/$id/.git" ]; then
    omarchy plugin update "$id" --yes || echo "  warning: update of $id failed; keeping the installed version" >&2
  elif [ -e "$PLUGINS_DIR/$id" ]; then
    echo "  $id is installed but not from git; leaving it as is."
  else
    omarchy plugin add "$url" --yes || {
      echo "  warning: could not add $id from $url" >&2
      FAILED=1
      return
    }
  fi
  place "$id" "$section"
}

# ── Backends ─────────────────────────────────────────────────────────────────
# The widgets can install these themselves from their panels, but only through
# a pkexec prompt, one widget at a time. Doing it here keeps a fresh machine
# from coming up with a bar full of "install me" buttons.
# Only the missing ones: `yay --needed` still runs `sudo pacman` for repo
# packages that are all installed (see install-apps.sh).
BACKENDS=()
need() { pacman -Qq "$1" &>/dev/null || BACKENDS+=("$1"); }
skipped aweiward.omaqbt || need qbittorrent-nox
skipped ayan.nordvpn || need nordvpn-bin
skipped local.omastat || need rust
if ((${#BACKENDS[@]})); then
  echo "Installing widget backends: ${BACKENDS[*]}"
  yay -S --noconfirm --needed "${BACKENDS[@]}"
fi

if ! skipped ayan.nordvpn; then
  # The same two things the widget's panel would otherwise ask to pkexec.
  systemctl is-enabled nordvpnd.service >/dev/null 2>&1 ||
    sudo systemctl enable --now nordvpnd.service
  if ! id -nG "$USER" | tr ' ' '\n' | grep -qx nordvpn; then
    sudo usermod -aG nordvpn "$USER"
    echo "  Added $USER to the nordvpn group -- takes effect at next login."
  fi
fi

# ── Git-managed widgets (id, repo, section as on the reference machine) ──────
git_plugin aweiward.omaqbt https://github.com/Aweiward/omaqbt.git left
git_plugin ayan.nordvpn https://github.com/AyanMulla09/OmaNord.git left
git_plugin io.github.ilyazar.syncthing https://github.com/omarchy-QOL/syncshell.git left
git_plugin omaplug https://github.com/fross100/omaplug center
git_plugin omamail https://github.com/huacnlee/omamail.git right
git_plugin io.github.jeremylanger.omaspotify https://github.com/jeremylanger/omaspotify.git right
git_plugin io.github.arthurr0.claude-usage https://github.com/arthurr0/omarchy-claude-usage.git right

# omaqbt's daemon unit is written by its own helper (the panel's "Start daemon"
# button runs exactly this). It also enables qBittorrent's Web UI on localhost,
# which is how the widget talks to it.
if ! skipped aweiward.omaqbt && [ -x "$PLUGINS_DIR/aweiward.omaqbt/qbt" ]; then
  if systemctl --user is-enabled omaqbt-nox.service >/dev/null 2>&1; then
    echo "omaqbt-nox.service already enabled."
  else
    "$PLUGINS_DIR/aweiward.omaqbt/qbt" start-daemon || echo "  warning: could not start the omaqbt daemon" >&2
  fi
fi

# ── Omastat (source build) ───────────────────────────────────────────────────
# Its widget needs the omastatd backend, which only ships as Rust source. The
# upstream install.sh builds it with cargo into ~/.cargo/bin, installs the user
# service, and installs the widget as `local.omastat` (a copy, not a git
# checkout -- hence it cannot go through git_plugin). The checkout lives at
# ~/Omastat, as on the reference machine. The cargo build takes minutes, so it
# is skipped when the installed widget already matches the pinned version.
#
# PINNED, not "latest tag": v0.2.0 renamed the project to Nagori -- new plugin id
# (local.nagori), daemon (nagorid), service and data dir, with no migration. Its
# install.sh does not touch local.omastat, so taking it runs BOTH trackers side
# by side on two bar slots, with the history split between them. Moving to
# Nagori is a deliberate switch (retire local.omastat + omastat.service, then
# change the id and paths below), not a version bump. OMASTAT_REF overrides.
if ! skipped local.omastat; then
  echo "==> local.omastat"
  OMASTAT_SRC="$HOME/Omastat"
  OMASTAT_REF="${OMASTAT_REF:-v0.1.6}"
  if [ -d "$OMASTAT_SRC/.git" ]; then
    git -C "$OMASTAT_SRC" fetch --tags --quiet || true
  else
    git clone --quiet https://github.com/ThisIsRinesi/Omastat.git "$OMASTAT_SRC"
  fi

  # Read the version out of the ref without checking it out, so a machine that
  # is already current keeps its checkout exactly as it was.
  want="$(git -C "$OMASTAT_SRC" show "$OMASTAT_REF:manifest.json" 2>/dev/null | jq -r .version 2>/dev/null || true)"
  have="$(jq -r .version "$PLUGINS_DIR/local.omastat/manifest.json" 2>/dev/null || true)"
  if [ -n "$want" ] && [ "$want" = "$have" ] && [ -x "$HOME/.cargo/bin/omastatd" ]; then
    echo "  Omastat $have already installed."
  elif ! git -C "$OMASTAT_SRC" -c advice.detachedHead=false checkout --quiet "$OMASTAT_REF"; then
    echo "  warning: could not check out Omastat $OMASTAT_REF in $OMASTAT_SRC" >&2
    FAILED=1
  else
    echo "  Building Omastat ${want:-?} (cargo; takes a few minutes)..."
    (cd "$OMASTAT_SRC" && ./install.sh) || {
      echo "  warning: Omastat install failed" >&2
      FAILED=1
    }
  fi
  place local.omastat right
fi

# ── Stock optional widgets ───────────────────────────────────────────────────
# Shipped with Omarchy, just switched on. omarchy.tailscale folds into Shibumi's
# fixed network group (G11) rather than taking a slot. install-tailscale.sh
# provides the daemon.
skipped omarchy.tailscale || place omarchy.tailscale right

if ! skipped omarchy.elsewhen; then
  place omarchy.elsewhen center
  # The world-clock zones the reference machine shows. Written only when the
  # entry has none yet, so zones edited on a machine are not reset on re-run.
  ZONES="New York|America/New_York, London|Europe/London, Dubai|Asia/Dubai, Tokyo|Asia/Tokyo, Los Angeles|America/Los_Angeles"
  if jq -e '[.bar.layout[]?[]? | select(.id == "omarchy.elsewhen" and (.zones // "") == "")] | length > 0' \
    "$SHELL_JSON" >/dev/null 2>&1; then
    tmp="$(mktemp "$SHELL_JSON.XXXXXX")"
    jq --arg z "$ZONES" '.bar.layout |= map_values(map(if .id == "omarchy.elsewhen" then .zones = $z else . end))' \
      "$SHELL_JSON" >"$tmp" && chmod --reference="$SHELL_JSON" "$tmp" && mv "$tmp" "$SHELL_JSON"
    echo "  Set omarchy.elsewhen zones."
  fi
fi

omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

cat <<'EOF'

Bar widgets installed. Per-machine sign-ins, all from the widget's own panel:
  NordVPN   log in (after re-login, for the nordvpn group)
  Omamail   add a mail account         Omaspotify  Spotify Premium login
  Syncthing pair devices / folders     Claude usage needs `claude` logged in
EOF

exit "$FAILED"
