#!/bin/bash

# Install Zsh
if ! command -v zsh &>/dev/null; then
    yay -S --noconfirm --needed zsh
fi

# Install (or repair) Oh My Zsh.
#
# Guard on the core loader file (oh-my-zsh.sh), NOT just the ~/.oh-my-zsh
# directory. A previous interrupted run -- or the `mkdir -p .../custom/plugins`
# below -- can create ~/.oh-my-zsh WITHOUT any of the core files. The old
# `[ -d ]` check then treated that broken state as "already installed" and
# skipped the installer forever, so oh-my-zsh.sh never appeared and .zshrc
# silently loaded zero plugins.
if [ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
  echo "Installing Oh My Zsh..."
  # The official installer aborts if ~/.oh-my-zsh already exists, so clear any
  # incomplete leftover first. In this broken state custom/plugins only holds
  # plugins this script re-clones below, so nothing user-authored is lost.
  rm -rf "$HOME/.oh-my-zsh"
  # KEEP_ZSHRC=yes preserves an existing ~/.zshrc (including the dotfiles
  # symlink) rather than overwriting it.
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# Only manage plugins once the core is actually present. If the install above
# failed (e.g. no network), bail out instead of recreating a phantom
# ~/.oh-my-zsh, so the next run retries the core install cleanly.
if [ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
  echo "Oh My Zsh core missing; skipping plugin install. Fix connectivity and re-run." >&2
else
  ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  mkdir -p "$ZSH_CUSTOM_DIR/plugins"

  # Clone a plugin only if it isn't already present. Keep this list in sync
  # with the plugins=(...) array in the dotfiles .zshrc.
  install_plugin() {
    local name="$1" url="$2" dest
    dest="$ZSH_CUSTOM_DIR/plugins/$name"
    [ -d "$dest" ] && return 0
    if ! git clone --depth 1 -- "$url" "$dest"; then
      echo "WARNING: failed to clone $name from $url" >&2
    fi
  }

  install_plugin zsh-autosuggestions      https://github.com/zsh-users/zsh-autosuggestions.git
  install_plugin zsh-syntax-highlighting  https://github.com/zsh-users/zsh-syntax-highlighting.git
  install_plugin fast-syntax-highlighting https://github.com/zdharma-continuum/fast-syntax-highlighting.git
  install_plugin zsh-autocomplete         https://github.com/marlonrichert/zsh-autocomplete.git
fi

# Install Starship prompt
if ! command -v starship &>/dev/null; then
  echo "Installing Starship..."
  yay -S --noconfirm --needed starship
fi

echo "Starship installed (config will be stowed from dotfiles)"
