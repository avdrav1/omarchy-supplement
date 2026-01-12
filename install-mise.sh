#!/bin/bash

# Install mise (tool/version manager)
# Official install script from https://github.com/jdx/mise

set -euo pipefail

# Ensure ~/.local/bin exists and is on PATH
mkdir -p "$HOME/.local/bin"

# Install mise via official installer
curl -fsSL https://mise.jdx.dev/install.sh | sh

# Inform the user where mise was installed
echo "mise installed. You may need to restart your shell for changes to take effect."
