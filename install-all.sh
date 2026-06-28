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

./install-stow.sh
./install-dotfiles.sh
./install-hyprland-overrides.sh
./set-shell.sh

./install-theme.sh

