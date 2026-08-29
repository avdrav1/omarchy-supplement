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

# The packaged systemd user unit is shipped disabled AND is broken as shipped:
# it sandboxes the daemon with ProtectSystem=strict plus
# ReadWritePaths=/run/user, which leaves $XDG_RUNTIME_DIR itself read-only. The
# daemon cannot then bind its IPC socket and exits 1 on every start:
#   [Socket] Failed to bind socket: Read-only file system
# %t expands to the runtime dir for user units, so this drop-in repairs it.
# Preferring the unit also keeps the daemon a single supervised instance --
# a second raw instance unlinks and takes over the socket, killing the first.
if [ -f /usr/lib/systemd/user/snappy-switcher.service ]; then
  override_dir="$HOME/.config/systemd/user/snappy-switcher.service.d"
  mkdir -p "$override_dir"
  cat >"$override_dir/override.conf" <<'EOF'
# Managed by install-snappy-switcher.sh -- see that script for the rationale.
[Service]
ReadWritePaths=%t
EOF
  systemctl --user daemon-reload
  systemctl --user enable snappy-switcher.service >/dev/null
fi

# Start the daemon now if inside a Hyprland session. The autostart line in the
# Hyprland overrides only fires at login, so a fresh install otherwise has no
# running daemon (and the ALT/SUPER+TAB binds silently do nothing) until the
# next logout. The pgrep guard keeps this re-runnable.
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && ! pgrep -x snappy-switcher >/dev/null; then
  # Prefer the unit; fall back for packages that predate it.
  #
  # Under Omarchy's Lua parser `hyprctl dispatch` evaluates Lua, so the hyprlang
  # form `hyprctl dispatch exec <cmd>` is a parse error rather than a dispatch
  # ("')' expected near ..."). With the output swallowed that read as success
  # while leaving no daemon behind, and the ALT/SUPER+TAB binds then silently did
  # nothing until the next login. Use the plugin-safe Lua namespace there, and
  # keep the legacy form for machines still on hyprlang.
  if ! systemctl --user start snappy-switcher.service 2>/dev/null; then
    if [ -f "$HOME/.config/hypr/hyprland.lua" ]; then
      hyprctl dispatch 'hl.dsp.exec_cmd("snappy-switcher --daemon")' >/dev/null 2>&1 || true
    else
      hyprctl dispatch exec "snappy-switcher --daemon" >/dev/null 2>&1 || true
    fi
  fi
fi

echo "snappy-switcher installation complete."
