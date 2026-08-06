#!/bin/bash

set -e

# Install tmux. Guard on the binary so a re-run on a provisioned machine skips
# yay entirely -- a bare `yay -S` pre-authenticates via sudo even when the
# package is already current, which fails in a non-interactive run.
command -v tmux &>/dev/null || yay -S --noconfirm --needed tmux

# Check if tmux is installed
if ! command -v tmux &>/dev/null; then
  echo "tmux installation failed."
  exit 1
fi

TPM_DIR="$HOME/.tmux/plugins/tpm"

# Check if TPM is already installed
if [ -d "$TPM_DIR" ]; then
  echo "TPM is already installed in $TPM_DIR"
else
  echo "Installing Tmux Plugin Manager (TPM)..."
  git clone https://github.com/tmux-plugins/tpm $TPM_DIR
fi

echo "TPM installed successfully!"