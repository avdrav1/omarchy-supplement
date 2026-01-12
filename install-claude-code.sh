#!/bin/bash

set -euo pipefail

# Install Claude Code CLI via official native installer
if command -v claude &>/dev/null; then
  echo "Claude Code (claude CLI) already installed."
  exit 0
fi

curl -fsSL https://claude.ai/install.sh | bash
