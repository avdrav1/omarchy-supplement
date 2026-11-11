#!/bin/bash
# zsh as the login shell, Oh My Zsh + plugins, and the starship pastel-powerline prompt
source "$(dirname "$0")/../lib/common.sh"

step "Oh My Zsh"
# Guard on the loader file, not the directory: an interrupted install can leave
# ~/.oh-my-zsh without its core, and the installer refuses an existing dir.
if [ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
  rm -rf "$HOME/.oh-my-zsh"
  # KEEP_ZSHRC keeps the dotfiles .zshrc (stowed by the dotfiles module).
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi
[ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ] || die "Oh My Zsh did not install (offline?)"

# Keep in sync with plugins=(...) in the dotfiles .zshrc.
ZSH_PLUGINS="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
while read -r name url; do
  [ -d "$ZSH_PLUGINS/$name" ] || git clone --quiet --depth 1 "$url" "$ZSH_PLUGINS/$name" ||
    warn "could not clone $name"
done <<'EOF'
zsh-autosuggestions      https://github.com/zsh-users/zsh-autosuggestions.git
zsh-syntax-highlighting  https://github.com/zsh-users/zsh-syntax-highlighting.git
fast-syntax-highlighting https://github.com/zdharma-continuum/fast-syntax-highlighting.git
zsh-autocomplete         https://github.com/marlonrichert/zsh-autocomplete.git
EOF

step "Login shell"
ZSH_PATH=$(command -v zsh)
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$ZSH_PATH" ]; then
  grep -qx "$ZSH_PATH" /etc/shells || echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
  sudo chsh -s "$ZSH_PATH" "$USER"
  note "login shell is now zsh (takes effect at next login)"
fi

step "Starship prompt"
# Generated from the installed starship (Omarchy ships it) rather than vendored,
# so the preset always matches the binary.
preset=$(starship preset pastel-powerline) || die "could not generate the pastel-powerline preset"
printf '%s\n' "$preset" | put "$HOME/.config/starship.toml"
