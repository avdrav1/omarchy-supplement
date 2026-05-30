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
  rm -rf ~/.zshrc ~/.config/nvim ~/.config/starship.toml ~/.local/share/nvim/ ~/.cache/nvim/ ~/.config/ghostty/config ~/.config/waybar/config.jsonc ~/.config/waybar/style.css ~/.config/waybar/scripts ~/.local/bin/audio-output-cycle

  cd "$REPO_NAME"
  stow zshrc
  stow ghostty
  stow tmux
  stow nvim
  stow starship
  stow mpd
  stow rmpc
  stow waybar
else
  echo "Failed to clone the repository."
  exit 1
fi

