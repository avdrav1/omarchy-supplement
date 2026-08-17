#!/bin/bash

# Run from this script's own directory so the ./install-*.sh calls resolve
# regardless of the caller's working directory (e.g. when invoked as
# ~/omarchy-supplement/install-all.sh from $HOME).
cd "$(dirname "$(readlink -f "$0")")" || exit 1

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
  sudo -n true
  sleep 60
  kill -0 "$_PARENT_PID" 2>/dev/null || exit
done &
_SUDO_KEEPALIVE_PID=$!
trap 'kill "$_SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

# Individual installers are intentionally non-fatal -- one broken installer
# shouldn't abort the whole provision. But a bare `./install-foo.sh` also makes
# a failure invisible: the run keeps going and still prints the manual-steps
# summary below, so it reads as success. Record failures and report them at the
# end instead.
FAILED=()

# Re-validate sudo before each installer.
#
# The keepalive above can only *extend* a live timestamp: `sudo -n` is
# non-interactive, so once the credential actually lapses it can never
# re-acquire one and every subsequent tick fails silently. That happens for
# real -- an installer that shells out to a tool with its own interactive sudo
# prompt (hyprpm) can sit at that prompt long enough for the keepalive to miss
# its window, and from then on the run is quietly rootless. The failure mode is
# nasty: yay still downloads and *builds* each package, then dies handing off to
# `pacman -U`, so installers fail minutes apart with all their work thrown away
# and nothing pointing at sudo.
#
# Checking at each installer boundary turns that into one prompt instead of a
# silent cascade.
_SUDO_DEAD=0
ensure_sudo() {
  ((_SUDO_DEAD)) && return 1
  sudo -n true 2>/dev/null && return 0
  echo "!! sudo credentials lapsed mid-run; re-authenticating..." >&2
  sudo -v && return 0
  _SUDO_DEAD=1
  echo "!! Could not re-acquire sudo (no tty?). Skipping the rest: every" >&2
  echo "!! remaining installer that needs root would build its package and" >&2
  echo "!! then fail handing off to pacman." >&2
  return 1
}

run() {
  local status=0
  if ! ensure_sudo; then
    FAILED+=("$* (skipped -- no sudo)")
    return 1
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
run ./install-postgresql.sh
run ./install-ghostty.sh
run ./install-tmux.sh
run ./install-github-desktop.sh
run ./install-claude-code.sh
run ./install-warp-terminal.sh
run ./install-claude-desktop.sh
run ./install-snappy-switcher.sh
run ./install-syncthing.sh
run ./install-tailscale.sh
run ./install-vivaldi.sh
run ./install-vscode.sh
run ./install-obsidian.sh
run ./install-slack.sh

run ./install-stow.sh
run ./install-dotfiles.sh
run ./install-hyprland-overrides.sh
# After hyprland-overrides so the plugin{} block and binds are already sourced
# when hyprpm loads the plugin.
run ./install-hyprland-scroll-overview.sh
run ./install-editor.sh
# After dotfiles stow so mbsync.timer exists before the installer enables it.
run ./install-aerc-mail.sh
run ./set-shell.sh

run ./install-theme.sh
# After the theme so Shibumi picks up Dos-Moos colors. install-shibumi.sh also
# retires the old Quickshell Rise bar this repo used to install.
run ./install-shibumi.sh

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
   - Claude Desktop, GitHub Desktop, Warp, Slack:  sign in on first launch.
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

6. Gmail / aerc (OAuth2, one-time per machine):
   - Google Cloud Console: new project -> enable Gmail API -> OAuth consent
     screen (External, PUBLISH) -> create OAuth client ID (Desktop app).
   - oama template > ~/.config/oama/config.yaml   # set GPG key + client_id/secret
   - oama authorize google <addr>  (per account), then `mbsync -a` and open aerc.

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

