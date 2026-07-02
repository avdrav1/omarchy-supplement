#!/bin/bash

ORIGINAL_DIR=$(pwd)
REPO_URL="https://github.com/avdrav1/dotfiles"
REPO_NAME="dotfiles"

is_stow_installed() {
  pacman -Qi "stow" &> /dev/null
}

if ! is_stow_installed; then
  echo "Install stow first"
  exit 1
fi

cd ~

# Check if the repository already exists
if [ -d "$REPO_NAME" ]; then
  echo "Repository '$REPO_NAME' already exists. Skipping clone"
else
  git clone "$REPO_URL"
fi

# Check if the clone was successful
if [ $? -eq 0 ]; then
  echo "removing old configs"
  rm -rf ~/.zshrc ~/.config/nvim ~/.config/starship.toml ~/.local/share/nvim/ ~/.cache/nvim/ ~/.config/ghostty/config ~/.local/bin/audio-output-cycle ~/.config/aerc ~/.config/isyncrc ~/.config/msmtp ~/.msmtprc

  cd "$REPO_NAME"
  stow zshrc
  stow ghostty
  stow tmux
  stow nvim
  stow starship
  # snappy-switcher's config dir gets folded into a single stow symlink, so
  # removing ~/.config/snappy-switcher/config.ini in the cleanup above would
  # delete the tracked file *through* that symlink, wiping it from the dotfiles
  # repo. Only clear a real (app-generated) dir here; never touch the symlink.
  [ -L ~/.config/snappy-switcher ] || rm -rf ~/.config/snappy-switcher
  stow snappy-switcher
  stow aerc-mail
  # Note: waybar stow removed - using Quickshell Rise bar instead
  # Note: mpd/rmpc stow removed - music tools not installed
else
  echo "Failed to clone the repository."
  exit 1
fi

