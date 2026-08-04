#!/bin/bash

set -euo pipefail

# Install and configure the Shibumi shell (a bundle of Quickshell plugins for
# the Omarchy shell -- the QS Rise V1/V2 layouts, controls, widgets and panels).
# https://github.com/HANCORE-linux/Shibumi-Shell
#
# Shibumi replaces Lacuna on this fleet (see the old install-lacuna.sh in git
# history). As of 0.1.x-beta it is NOT yet on the AUR, so this uses the
# project's documented "transitional source" install: clone the repo and run
# its `shibumi-suite install`, which stages the ~24 user plugins into
# ~/.config/omarchy and writes only user-scoped plugin state (no sudo).
#
# When shibumi-shell lands on the AUR the upstream install collapses to
#   omarchy pkg aur add shibumi-shell && shibumi-shell install --yes
# at which point this script should be rewritten to mirror the (now-removed)
# lacuna installer's `pacman -Qi` + CLI shape. Until then we track a git
# checkout and re-stage from it.
#
# Re-runnable: pulls the checkout up to date and re-runs the suite installer,
# which restages plugins to their canonical state each time.

SHIBUMI_REPO="${SHIBUMI_REPO:-https://github.com/HANCORE-linux/Shibumi-Shell.git}"
SHIBUMI_SRC="${SHIBUMI_SRC:-$HOME/.local/share/shibumi-shell}"
SHIBUMI_TERMINAL="${SHIBUMI_TERMINAL:-ghostty}"

# 0. Tear down a prior Lacuna install if present, so a machine mid-migration
#    converges to the Shibumi-only state instead of running both shells' widgets
#    side by side. Both steps are best-effort (|| true): unstaging backs plugins
#    up under ~/.config/omarchy/plugins/*.bak.*, and the package drop needs sudo
#    (skipped silently in a non-interactive/first-boot context). Idempotent --
#    a no-op once Lacuna is gone.
if command -v lacuna-shell &>/dev/null; then
  echo "Lacuna detected; removing it before installing Shibumi."
  lacuna-shell uninstall --all --yes || true
  yay -Rns --noconfirm lacuna-shell || true
fi

# 1. Runtime dependencies (repo + AUR fonts). yay handles both and only sudos
#    for the actual package install; --needed skips already-present packages.
yay -S --noconfirm --needed \
  python jq curl networkmanager power-profiles-daemon upower xdg-utils \
  libnotify wl-clipboard \
  ttf-material-symbols-variable ttf-jetbrains-mono-nerd-basic \
  noto-fonts-cjk adwaita-fonts

# 2. Fetch/refresh the Shibumi source checkout.
if [ -d "$SHIBUMI_SRC/.git" ]; then
  echo "Updating Shibumi checkout in $SHIBUMI_SRC"
  git -C "$SHIBUMI_SRC" pull --ff-only
else
  echo "Cloning Shibumi into $SHIBUMI_SRC"
  mkdir -p "$(dirname "$SHIBUMI_SRC")"
  git clone "$SHIBUMI_REPO" "$SHIBUMI_SRC"
fi

# 3. Stage the Shibumi plugins into the Omarchy shell. --yes skips the prompt.
#    User-scoped, so no sudo here.
"$SHIBUMI_SRC/scripts/shibumi-suite" install --yes

# 4. Point Omarchy's default terminal (what the shell's terminal button launches
#    via xdg-terminal-exec) at ghostty. Shell-agnostic Omarchy config, carried
#    over from the Lacuna setup.
if command -v "$SHIBUMI_TERMINAL" &>/dev/null; then
  omarchy default terminal "$SHIBUMI_TERMINAL"
  echo "Omarchy default terminal set to '$SHIBUMI_TERMINAL'."
else
  echo "'$SHIBUMI_TERMINAL' not found; leaving Omarchy default terminal unchanged."
  echo "Install it (e.g. ./install-ghostty.sh) and re-run to switch the terminal."
fi

# 5. Restart the Omarchy shell so it picks up the staged plugins. Only
#    meaningful inside a running Wayland session; guard so the script is safe in
#    a TTY / first-boot provisioning context (install-all.sh) where no shell is
#    up yet.
if command -v omarchy-restart-shell &>/dev/null && [ -n "${WAYLAND_DISPLAY:-}" ]; then
  omarchy-restart-shell || echo "omarchy-restart-shell failed; run it manually to apply changes."
else
  echo "No Wayland session detected; run 'omarchy-restart-shell' after login to apply."
fi

echo "Shibumi installation and configuration complete."
