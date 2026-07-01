#!/bin/bash

set -euo pipefail

# Install Tailscale (WireGuard-based zero-config VPN) from the official Arch
# repo and enable the tailscaled system service.
#
# Tailscale provides a stable 100.x.y.z address per machine on the tailnet,
# independent of local network topology. Syncthing here uses those addresses
# to connect directly to peers that are behind a downstream mesh router
# (different subnet, no LAN discovery). Without this, Syncthing falls back
# to public relays.
#
# `tailscale up` needs interactive browser auth on first run and cannot be
# done unattended, so this script installs and enables the daemon and then
# prints the command the user must run themselves.

if pacman -Qi tailscale &>/dev/null; then
  echo "Tailscale already installed."
else
  sudo pacman -S --noconfirm --needed tailscale
fi

sudo systemctl enable --now tailscaled.service

if tailscale status &>/dev/null; then
  echo "Tailscale already logged in:"
  tailscale status | head -5
else
  echo ""
  echo "Tailscale installed. Complete authentication with:"
  echo "  sudo tailscale up"
  echo ""
  echo "Follow the printed URL in a browser and sign in to the same account"
  echo "used on the other devices (av-framework, av-alienware)."
fi
