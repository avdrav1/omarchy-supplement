#!/bin/bash

# Run from this script's own directory so the ./install-*.sh calls resolve
# regardless of the caller's working directory (e.g. when invoked as
# ~/omarchy-supplement/install-all.sh from $HOME).
cd "$(dirname "$(readlink -f "$0")")" || exit 1

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
run() {
  local status=0
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
   - Quickshell Rise bar starts via the post-boot autostart hook. On Omarchy 4
     (quattro) it also hides the stock omarchy bar; to hand that back, re-run
     the upstream installer with --no-autostart.
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

