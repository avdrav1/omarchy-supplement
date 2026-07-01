#!/bin/bash

set -euo pipefail

# Install Syncthing (continuous file synchronization) from the official Arch
# repo and enable it as a per-user systemd service.
#
# Syncthing generates its own config and TLS device identity in
# ~/.local/state/syncthing on first run. That directory holds secrets
# (key.pem, and the GUI apikey inside config.xml) plus a machine-specific
# database, so it is intentionally NOT tracked in the dotfiles repo.
# Configure folders and pair devices via the web UI at http://127.0.0.1:8384.

if pacman -Qi syncthing &>/dev/null; then
  echo "Syncthing already installed."
else
  sudo pacman -S --noconfirm --needed syncthing
fi

# Enable the per-user service (ships at /usr/lib/systemd/user/syncthing.service)
# so Syncthing starts on login.
if command -v systemctl &>/dev/null; then
  systemctl --user enable --now syncthing.service 2>/dev/null || true
fi

echo "Syncthing installed and user service enabled. Web UI: http://127.0.0.1:8384"
