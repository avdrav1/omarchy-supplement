#!/bin/bash

# Install stow. Guard on the binary so a re-run on a provisioned machine skips
# yay entirely -- a bare `yay -S` pre-authenticates via sudo even when the
# package is already current, which fails in a non-interactive run and reports
# a spurious install-all.sh failure.
command -v stow &>/dev/null || yay -S --noconfirm --needed stow
