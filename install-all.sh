#!/bin/bash

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

./install-stow.sh
./install-dotfiles.sh
./install-hyprland-overrides.sh
./set-shell.sh

./install-theme.sh
./install-waybar-theme.sh