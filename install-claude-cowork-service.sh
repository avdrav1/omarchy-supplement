#!/bin/bash

set -euo pipefail

# Install the native Linux backend for Claude Desktop's Cowork feature.
#
# Cowork lets Claude Desktop delegate tasks to a sandboxed Claude Code instance.
# Linux has no official backend, so this daemon implements the socket protocol
# Claude Desktop expects (native backend by default; KVM is opt-in/experimental).
# Source: https://github.com/patrickjaja/claude-cowork-service (AUR: claude-cowork-service)
#
# Runtime requirement: the `claude` CLI (Claude Code) must be on PATH. It is
# installed by install-claude-code.sh, which runs earlier in install-all.sh.

if ! command -v claude &>/dev/null; then
  echo "Warning: 'claude' (Claude Code) not found on PATH."
  echo "Cowork spawns 'claude' for every task; install it first (install-claude-code.sh)."
fi

# Install the daemon from the AUR (skip if already present; update via yay -Syu).
if pacman -Qq claude-cowork-service &>/dev/null; then
  echo "claude-cowork-service already installed."
else
  yay -S --needed --noconfirm claude-cowork-service
fi

# Enable and start the per-user daemon. Claude Desktop connects to it over a
# Unix socket. Don't hard-fail provisioning if there's no active user session
# (e.g. running over plain SSH) -- just print the command to run later.
if systemctl --user enable --now claude-cowork.service; then
  echo "claude-cowork.service enabled and started."
else
  echo "Could not enable claude-cowork.service automatically (no systemd user session?)."
  echo "Enable it later from your desktop session with:"
  echo "  systemctl --user enable --now claude-cowork.service"
fi
