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
  rm -rf ~/.zshrc ~/.config/nvim ~/.local/share/nvim/ ~/.cache/nvim/ ~/.config/ghostty/config ~/.local/bin/audio-output-cycle ~/.config/aerc ~/.config/isyncrc ~/.config/msmtp ~/.msmtprc ~/.config/Code/User/settings.json ~/.config/Code/User/keybindings.json ~/.config/fcitx5/conf/quickphrase.conf

  cd "$REPO_NAME"
  stow zshrc
  stow ghostty
  stow tmux
  stow nvim
  # starship is deliberately NOT stowed: ~/.config/starship.toml is owned by
  # install-starship.sh, which generates the upstream pastel-powerline preset.
  # The dotfiles repo still carries a starship package (its own peach/lavender
  # theme) -- stowing it here would symlink that over the preset, since this
  # installer runs first. Keep it out of both this list and the rm -rf above.
  # snappy-switcher's config dir gets folded into a single stow symlink, so
  # removing ~/.config/snappy-switcher/config.ini in the cleanup above would
  # delete the tracked file *through* that symlink, wiping it from the dotfiles
  # repo. Only clear a real (app-generated) dir here; never touch the symlink.
  [ -L ~/.config/snappy-switcher ] || rm -rf ~/.config/snappy-switcher
  stow snappy-switcher
  stow aerc-mail
  # Ensure VSCode's config dir exists as a real dir first so stow symlinks only
  # the individual files (settings.json, keybindings.json). Otherwise stow would
  # fold the whole ~/.config/Code into a single symlink and VSCode's runtime
  # state (globalStorage, History, workspaceStorage) would land in the repo.
  mkdir -p ~/.config/Code/User
  stow vscode
  # Only quickphrase.conf is tracked -- it clears the fcitx5 "Quick Phrase"
  # addon's default Super+grave / Super+semicolon triggers, which collided with
  # the workspace-overview bind on SUPER+` (hypr/lua/scrolloverview.lua): both
  # fired on every press. Same folding trap as vscode above -- on a machine
  # where fcitx5 has never run, ~/.config/fcitx5 doesn't exist and stow would
  # fold the whole dir into one symlink, dumping fcitx5's runtime state
  # (profile, cached_layouts) into the repo. Create the real dirs first so only
  # the single file is linked.
  mkdir -p ~/.config/fcitx5/conf
  stow fcitx5
  # The dotfiles repo now contains only the packages stowed above. The X11-era
  # and pre-Omarchy packages (i3, picom, polybar, rofi, wofi, waybar,
  # xresources, screenlayout, alacritty, kitty, elephant, backgrounds,
  # dns-health-check) and the music-tool configs (mpd, rmpc) were deleted --
  # recover them from git history if ever needed.
  #
  # Hyprland configs are deliberately NOT here: Omarchy owns ~/.config/hypr,
  # and this repo's overrides go through install-hyprland-overrides.sh. The old
  # dotfiles hyprland/hyprlock/hyprpaper/hyprmocha packages were removed because
  # they still carried a pre-Omarchy hyprland.conf (its own monitor scale, and
  # `hyprctl keyword` binds that no longer work under the Lua parser), which
  # made them a trap when debugging display scaling.
else
  echo "Failed to clone the repository."
  exit 1
fi

