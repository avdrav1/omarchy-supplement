#!/bin/bash

set -euo pipefail

# Install Kiro CLI via official installer
if command -v kiro-cli &>/dev/null; then
  echo "Kiro CLI already installed."
  exit 0
fi

curl -fsSL https://cli.kiro.dev/install | bash
