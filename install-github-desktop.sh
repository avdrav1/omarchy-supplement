#!/bin/bash

# Install GitHub Desktop (AUR package: github-desktop-bin)

set -euo pipefail

yay -S --noconfirm --needed github-desktop-bin

echo "GitHub Desktop installation complete."
