#!/bin/bash

# Run from this script's own directory so the ./install-*.sh calls resolve
# regardless of the caller's working directory (e.g. when invoked as
# ~/omarchy-supplement/install-all.sh from $HOME).
cd "$(dirname "$(readlink -f "$0")")" || exit 1

# Install all packages in order
./install-zsh.sh
./install-mise.sh
./install-asdf.sh
./install-nodejs.sh
./install-ruby.sh
./install-postgresql.sh
./install-ghostty.sh
./install-tmux.sh
./install-github-desktop.sh
./install-claude-code.sh
./install-warp-terminal.sh
./install-claude-desktop.sh
./install-claude-cowork-service.sh
./install-snappy-switcher.sh
./install-syncthing.sh
./install-tailscale.sh
./install-vivaldi.sh

./install-stow.sh
./install-dotfiles.sh
./install-hyprland-overrides.sh
./install-editor.sh
# After dotfiles stow so mbsync.timer exists before the installer enables it.
./install-aerc-mail.sh
./set-shell.sh

./install-theme.sh

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
   - Quickshell Rise bar starts via the post-boot autostart hook.
   - Open terminals/aerc pick up the new $EDITOR (fresh) and mise on PATH.

2. Display scale (per machine):
   - Edit hosts/<hostname>.conf and set $MONSCALE (e.g. 1.5 HiDPI, 1 native).
   - Apply + persist:  hyprctl reload  then commit hosts/<hostname>.conf

3. Sign in to apps (no automated auth):
   - Claude Code CLI:  run `claude` and authenticate.
   - Claude Desktop, GitHub Desktop, Warp:  sign in on first launch.
   - Vivaldi:  optional Vivaldi Sync; re-add Mail/Calendar accounts per machine.

4. Syncthing:  open http://127.0.0.1:8384 to add folders and pair devices.

5. Gmail / aerc (OAuth2, one-time per machine):
   - Google Cloud Console: new project -> enable Gmail API -> OAuth consent
     screen (External, PUBLISH) -> create OAuth client ID (Desktop app).
   - oama template > ~/.config/oama/config.yaml   # set GPG key + client_id/secret
   - oama authorize google <addr>  (per account), then `mbsync -a` and open aerc.

============================================================
EOF

