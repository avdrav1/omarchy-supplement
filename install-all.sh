#!/bin/bash

# Run from this script's own directory so the ./install-*.sh calls resolve
# regardless of the caller's working directory (e.g. when invoked as
# ~/omarchy-supplement/install-all.sh from $HOME).
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# Pull this repo first, so a laptop re-running install-all.sh applies the fleet's
# current config rather than whatever it last checked out. Syncthing is not a
# reliable carrier (see .stignore -- it deliberately skips .git, and a host can
# have no folders configured at all), so GitHub is the source of truth.
#
# Fast-forward only: a machine with local commits or edits keeps them and gets a
# warning instead of a merge. When HEAD moves, re-exec so the rest of the run is
# the NEW install-all.sh, not the copy bash already has in memory.
# SUPPLEMENT_NO_PULL=1 skips this (e.g. testing uncommitted changes).
if [ "${SUPPLEMENT_NO_PULL:-0}" = 0 ] && [ -d .git ]; then
  _before=$(git rev-parse HEAD 2>/dev/null)
  if git pull --ff-only --quiet 2>/dev/null; then
    if [ "$(git rev-parse HEAD)" != "$_before" ]; then
      echo "==> omarchy-supplement updated ($(git log --oneline -1)); restarting."
      SUPPLEMENT_NO_PULL=1 exec "$0" "$@"
    fi
  else
    echo "!! Could not fast-forward omarchy-supplement (local changes, diverged" >&2
    echo "!! history, or offline). Continuing with the checked-out version." >&2
  fi
fi

# A repo section declared twice in pacman.conf makes libalpm refuse to register
# that database. pacman itself only warns and carries on, but yay treats the
# failed registration as fatal and exits before doing anything -- so every AUR
# installer below dies with an error that never mentions pacman.conf. Catch it
# here, where the message can point at the actual cause.
_dupe_repos=$(awk -F'[][]' '/^\[/ && $2 != "options" {c[$2]++} END {for (r in c) if (c[r] > 1) print r}' /etc/pacman.conf)
if [ -n "$_dupe_repos" ]; then
  echo "!! Duplicate repo section(s) in /etc/pacman.conf:" >&2
  printf '!!   [%s]\n' $_dupe_repos >&2
  echo "!! libalpm cannot register a database twice, so yay fails on every AUR" >&2
  echo "!! package. Delete the duplicate block(s), then re-run." >&2
  exit 1
fi

# Authenticate sudo ONCE up front. Nearly every installer below needs root
# (pacman/yay/systemctl). Without a warmed credential each one authenticates
# separately, and in a non-interactive run (no tty) they fail one by one and
# pile up in the failure summary as spurious errors -- even on a machine that is
# already fully provisioned. Prompt once here, fail fast with an actionable
# message when there's no tty, and keep the timestamp alive for the whole run
# (plugin/AUR builds can exceed sudo's default 15-minute timeout).
if ! sudo -v; then
  echo "!! This installer needs sudo. Run it in an interactive terminal, or" >&2
  echo "!! configure passwordless sudo for pacman/systemctl, then re-run." >&2
  exit 1
fi
_PARENT_PID=$$
while true; do
  sudo -n true 2>/dev/null
  sleep 60
  kill -0 "$_PARENT_PID" 2>/dev/null || exit
done &
_SUDO_KEEPALIVE_PID=$!
trap 'kill "$_SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

# The keepalive above is best-effort, not a guarantee: `sudo -n` can only extend
# a *live* credential, so once the timestamp lapses for any reason (a long
# hyprpm/AUR build stalling the loop, hyprpm's own sudo calls, a policy that
# expires the ticket) it can never recover it -- it just fails silently every
# 60s for the rest of the run. That is exactly what leaves a run where the first
# dozen installers succeed and every later one that needs root fails at once.
#
# So re-check in the FOREGROUND before each installer, where there is still a
# tty to prompt on, and re-authenticate if the credential is gone.
#
# When even that fails there is no tty at all, and every remaining installer
# that needs root would download and *build* its package before dying at the
# `pacman -U` handoff -- minutes of work each, thrown away, with nothing in the
# error pointing at sudo. Latch that state and skip the rest instead.
_SUDO_DEAD=0
sudo_refresh() {
  ((_SUDO_DEAD)) && return 1
  sudo -n true 2>/dev/null && return 0
  echo "!! sudo credential lapsed -- re-authenticating." >&2
  sudo -v && return 0
  _SUDO_DEAD=1
  echo "!! Could not re-acquire sudo (no tty?). Skipping every remaining" >&2
  echo "!! installer that needs root." >&2
  return 1
}

# Individual installers are intentionally non-fatal -- one broken installer
# shouldn't abort the whole provision. But a bare `./install-foo.sh` also makes
# a failure invisible: the run keeps going and still prints the manual-steps
# summary below, so it reads as success. Record failures and report them at the
# end instead.
FAILED=()

run() {
  local status=0
  # Fail the installer here rather than letting it die halfway through a
  # pacman/yay call it can no longer authenticate.
  if ! sudo_refresh; then
    echo "!! FAILED: $* (no sudo credential)" >&2
    FAILED+=("$*")
    return
  fi
  # Capture the status directly -- inside `if ! "$@"` the `!` has already
  # rewritten $? to 0, so reading it in the branch always reports success.
  "$@" || status=$?
  if ((status != 0)); then
    echo "!! FAILED: $* (exit $status)" >&2
    FAILED+=("$*")
  fi
}

# Install all packages in order
run ./install-zsh.sh
run ./install-mise.sh
run ./install-asdf.sh
run ./install-nodejs.sh
run ./install-ruby.sh
run ./install-ghostty.sh
run ./install-tmux.sh
run ./install-github-desktop.sh
run ./install-claude-code.sh
run ./install-claude-desktop.sh
run ./install-syncthing.sh
run ./install-tailscale.sh
run ./install-vivaldi.sh
run ./install-vscode.sh
run ./install-obsidian.sh
run ./install-slack.sh
# Apps + web apps the reference machine has that no dedicated installer covers.
# Needs yay (Omarchy base) and omarchy-webapp-install; no other ordering needs.
run ./install-apps.sh
# Installed from a GitHub release rather than the AUR, so it only needs curl and
# the pacman deps -- no ordering constraint against the runtimes above. Kept
# before install-hyprland-overrides.sh purely so the binary exists by the time
# that installer lands the SUPER+SHIFT+F binds pointing at it.
run ./install-strata.sh

run ./install-stow.sh
run ./install-dotfiles.sh
# After dotfiles: it clears and re-stows ~/.config, so the starship preset has
# to be written afterwards or a leftover `stow starship` symlink wins.
run ./install-starship.sh
run ./install-hyprland-overrides.sh
# After hyprland-overrides so the plugin{} block and binds are already sourced
# when hyprpm loads the plugin.
run ./install-hyprland-scroll-overview.sh
run ./install-editor.sh
# After dotfiles stow so mbsync.timer exists before the installer enables it.
run ./install-aerc-mail.sh
run ./set-shell.sh

run ./install-theme.sh
# After the theme so Shibumi picks up the Solitude colors. install-shibumi.sh also
# retires the old Quickshell Rise bar this repo used to install.
run ./install-shibumi.sh
# After Shibumi: it branches on which bar is installed, and rewrites the group
# layout Shibumi's installer has just laid down.
run ./install-sync-calendar.sh
# After Shibumi and the calendar clock: it appends its bar widget to the same
# shell.json group layout those two lay down, and reads the run's length to find
# a free slot -- so it has to see the final arrangement, not an intermediate one.
run ./install-blueferry.sh
# After everything that lays out bar groups (Shibumi, calendar clock, BlueFerry):
# the remaining third-party widgets only get placed when not already on the bar,
# and Shibumi's reconciler then fills whatever v2Layout slots are still free --
# so the widgets with dedicated installers above get first claim on the slots.
run ./install-bar-plugins.sh
# After Shibumi so omarchy-shell is settled. Unlike the bar installers above it is a
# *service* plugin, so it only needs shell.json's `plugins` array and never
# touches the bar layout -- but it still wants to land before the final shell
# restart below. Its Hyprland binds come from install-hyprland-overrides.sh.
run ./install-quickswitch.sh
# LAST: it clones+patches the omarchy.menu plugin and edits the same shell.json
# Shibumi's installer rewrites, so it has to run after that settles -- and its
# shell restart should be the final one of the provision.
run ./install-omarchy-menu-websearch.sh

# ── Manual steps ─────────────────────────────────────────────────────────────
# Everything above is automated; the items below need a human (interactive
# sign-ins, session restart, per-machine values). The individual installers
# print these too, but they scroll away, so summarize them here at the end.
cat <<'EOF'

============================================================
  Manual steps to finish setup
============================================================

1. Log out and back in (or reboot) to apply session changes:
   - zsh becomes your default shell (chsh).
   - Shibumi Shell runs inside the stock omarchy-shell (installed as Omarchy
     plugins), so no separate autostart is needed. install-shibumi.sh turns the
     stock bar back on and restarts the shell; a fresh login also picks it up.
   - Open terminals/aerc pick up the new $EDITOR (fresh) and mise on PATH.

2. Display scale (per machine):
   - Omarchy quattro (Lua config, ~/.config/hypr/hyprland.lua present):
       Edit hypr/lua/hosts/<hostname>.lua and set scale (1.5 HiDPI, 1 native),
       then re-run ./install-hyprland-overrides.sh and hyprctl reload.
       The re-run is REQUIRED: it regenerates ~/.config/hypr/monitors.lua, which
       omarchy-hyprland-monitor-clamshell greps every 2s to reapply the scale.
       Wait ~5s before checking hyprctl monitors -- that poll can return a
       stale value immediately after a reload.
   - Legacy (.conf config):
       Edit hosts/<hostname>.conf, set $MONSCALE, then hyprctl reload.
   - Either way, commit the host file.

3. Sign in to apps (no automated auth):
   - Claude Code CLI:  run `claude` and authenticate.
   - Claude Desktop, GitHub Desktop, Slack:  sign in on first launch.
   - Vivaldi:  optional Vivaldi Sync; re-add Mail/Calendar accounts per machine.

4. Syncthing:  open http://127.0.0.1:8384 to add folders and pair devices.

5. Hyprland plugins (hyprpm):  after EVERY Hyprland upgrade, rebuild or the
   scroll-overview plugin silently stops loading -- SUPER+` just does nothing.
   Under the Lua config there is no error to notice: hypr/lua/scrolloverview.lua
   no-ops when the plugin is absent (the old .conf setup at least showed
   "Invalid dispatcher" in `hyprctl configerrors`). To rebuild:
       hyprpm update && hyprpm reload
   A pacman hook prints this reminder post-upgrade; it can't run the rebuild
   itself because hyprpm needs an interactive sudo.

6. Omarchy menu web-search fallback:  after every `omarchy update`, re-run
   ./install-omarchy-menu-websearch.sh
   It clones and patches the omarchy.menu plugin, so an Omarchy release that
   ships a new menu leaves the clone frozen on the old one. The re-run
   re-clones from the updated /usr/share/omarchy and re-applies the patch.

7. Calendar Sync clock (per machine):  the bar clock renders empty until it has
   a feed. Click it -> settings gear -> Add Calendar, or write
   ~/.config/omarchy/calendars.json directly (it hot-reloads). That file holds
   private .ics URLs and JMAP bearer tokens, so it is deliberately NOT tracked
   in this repo and does not sync -- add feeds on each machine.
   Two traps, both of which sync "successfully" and just show nothing:
   - Keep the outer [ ] -- the file is an ARRAY of calendars. A bare object
     makes fetch-events.py die on an AttributeError nothing surfaces.
   - Check the calendar id inside the URL (.../ical/<id>/private-.../basic.ics)
     is the account you actually use. A Google secret address copied from the
     wrong account fetches fine and reports status "ok" with no events.
   Google Workspace hides the secret address until an admin sets Calendar ->
   Sharing settings -> External sharing options to one of the bottom two.

8. BlueFerry (iPhone messages):  pairing is interactive and per machine.
   Keep the iPhone unlocked on Settings -> Bluetooth, press SUPER+M (or run
   `blueferry pair-setup`), then Scan -> select the phone -> Pair and confirm
   the same code on both sides; it can take ~15s to appear. Afterwards tap the
   (i) beside this computer ON THE PHONE and enable "Show Message
   Notifications" and "Sync Contacts" -- if those toggles are missing, back out
   to the device list and reopen the (i) page a few times. Approve "Allow
   System Notifications" and the desktop wallet prompt too.
   Without the notification permission, messages and contacts still work but a
   group message can look like a direct one from whoever sent it.
   Check with `blueferry doctor` / `journalctl --user -u blueferry -f`.

9. Gmail / aerc (OAuth2, one-time per machine):
   - Google Cloud Console: new project -> enable Gmail API -> OAuth consent
     screen (External, PUBLISH) -> create OAuth client ID (Desktop app).
   - oama template > ~/.config/oama/config.yaml   # set GPG key + client_id/secret
   - oama authorize google <addr>  (per account), then `mbsync -a` and open aerc.

10. Bar widgets (install-bar-plugins.sh), each signed in from its own panel:
   NordVPN (log out/in first -- the nordvpn group is new), Omamail (mail
   account), Omaspotify (Spotify Premium), Syncthing (pair devices), Claude
   usage (needs `claude` logged in). Apps: 1Password, Discord, Codex.

============================================================
EOF

# Surface anything that failed. Printed after the manual steps so it is the last
# thing on screen rather than something that scrolled past an hour ago.
if ((${#FAILED[@]} > 0)); then
  echo
  echo "============================================================"
  echo "  ${#FAILED[@]} installer(s) FAILED -- setup is incomplete"
  echo "============================================================"
  printf '  - %s\n' "${FAILED[@]}"
  echo
  echo "  Re-run each one directly to see its error."
  echo "============================================================"
  exit 1
fi

