#!/bin/bash
# Clone or update avdrav1/dotfiles and stow its packages into $HOME
source "$(dirname "$0")/../lib/common.sh"

DOTFILES="$HOME/dotfiles"
REPO_URL="https://github.com/avdrav1/dotfiles"

# Linked file by file (`stow --no-folding`), so a directory an app also writes
# runtime state into (~/.config/Code, ~/.config/vesktop, ~/.config/omarchy...)
# stays a real directory and that state never lands in the repo.
FILE_PACKAGES=(zshrc ghostty aerc-mail vscode fcitx5 vesktop herdr)
# Linked as a whole directory: the repo owns the entire config.
DIR_PACKAGES=(nvim)
# Not stowed: `starship` (modules/20-shell.sh writes the upstream preset instead).

step "Dotfiles repo"
if [ -d "$DOTFILES/.git" ]; then
  git -C "$DOTFILES" pull --ff-only --quiet 2>/dev/null ||
    warn "could not fast-forward ~/dotfiles; stowing the checked-out version"
else
  git clone --quiet "$REPO_URL" "$DOTFILES"
fi

# True when <path> already resolves into the dotfiles repo -- either a stow link
# itself or a file reached through one.
ours() { [[ $(readlink -f "$1") == "$DOTFILES"/* ]]; }

# Move a file Omarchy (or an app) put where a dotfile goes out of the way, as
# <path>.pre-stow, so stow can link ours. Never touches links stow already made.
make_way() {
  local target="$1"
  [ -e "$target" ] || [ -L "$target" ] || return 0
  ours "$target" && return 0
  mv "$target" "$target.pre-stow.$(date +%s)"
  note "moved aside $target"
}

step "Stow"
for p in "${FILE_PACKAGES[@]}"; do
  while IFS= read -r f; do
    make_way "$HOME/${f#"$p"/}"
  done < <(cd "$DOTFILES" && find "$p" -type f)
  stow -d "$DOTFILES" -t "$HOME" --no-folding -R "$p"
done

for p in "${DIR_PACKAGES[@]}"; do
  while IFS= read -r d; do
    target="$HOME/${d#"$p"/}"
    if ! ours "$target" && [ -e "$target" ]; then
      make_way "$target"
      # Omarchy's own nvim config (LazyVim) leaves plugins and state behind that
      # don't match ours; they are re-downloaded on first launch.
      [ "$p" = nvim ] && rm -rf "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"
    fi
  done < <(cd "$DOTFILES" && find "$p" -mindepth 2 -maxdepth 2 -type d)
  stow -d "$DOTFILES" -t "$HOME" -R "$p"
done
