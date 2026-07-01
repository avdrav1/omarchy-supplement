#!/bin/bash

# Install snappy-switcher: a fast, animated Alt+Tab window switcher for
# Hyprland (AUR package: snappy-switcher).
#
# Hyprland wiring (daemon autostart + ALT/SUPER+TAB binds) lives in
# hyprland-overrides.conf and is applied by install-hyprland-overrides.sh.
# The user config.ini ships from the dotfiles repo via `stow snappy-switcher`.

set -euo pipefail

if pacman -Qi snappy-switcher &>/dev/null; then
  echo "snappy-switcher already installed."
else
  yay -S --noconfirm --needed snappy-switcher
fi

# Start the daemon now if inside a Hyprland session. The exec-once line in
# hyprland-overrides.conf only fires at login, so a fresh install otherwise has
# no running daemon (and the ALT/SUPER+TAB binds silently do nothing) until the
# next logout. The pgrep guard keeps this re-runnable.
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && ! pgrep -f 'snappy-switcher --daemon' >/dev/null; then
  hyprctl dispatch exec "snappy-switcher --daemon" >/dev/null 2>&1 || true
fi

echo "snappy-switcher installation complete."
