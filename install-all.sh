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
./install-stow.sh
./install-dotfiles.sh
./install-hyprland-overrides.sh
./install-github-desktop.sh

./set-shell.sh
