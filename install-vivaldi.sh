#!/bin/bash

set -euo pipefail

# Install the Vivaldi browser (and its proprietary-codec package for H.264 /
# Widevine DRM playback) from the official Arch repo.
#
# Note: Vivaldi's profile, settings, and built-in Mail data live in
# ~/.config/vivaldi (an 11GB+ live Chromium profile with secrets encrypted by a
# per-machine os_crypt key). It is intentionally NOT tracked in dotfiles. To
# carry general browser settings across machines use Vivaldi Sync
# (vivaldi.net); Mail/Calendar/Feed accounts are local per install and must be
# re-added on each device.

if pacman -Qi vivaldi &>/dev/null; then
  echo "Vivaldi already installed."
else
  sudo pacman -S --noconfirm --needed vivaldi vivaldi-ffmpeg-codecs
fi

echo "Vivaldi installation complete."
