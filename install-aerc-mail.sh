#!/bin/bash

set -euo pipefail

# Install a text-config, dotfiles-syncable mail stack for Gmail (OAuth2):
#   aerc                - TUI mail client (reads a local Maildir, sends via msmtp)
#   isync               - mbsync: IMAP <-> Maildir sync
#   msmtp               - SMTP sending (xoauth2 built in)
#   oama                - OAuth2 token manager (authorize + auto-refresh)
#   cyrus-sasl-xoauth2  - XOAUTH2 SASL mechanism so isync can use OAuth2
#   pass / w3m          - GPG secret store / render text/html in aerc
#
# The configs (accounts, servers, rules) live in the dotfiles repo as the
# `aerc-mail` stow package. No secrets in dotfiles: mbsync and msmtp obtain a
# fresh access token at runtime via `oama access <addr>`; oama keeps the OAuth
# tokens GPG-encrypted under ~/.local/state/oama.
#
# A systemd --user timer (mbsync.timer, shipped in the aerc-mail dotfiles
# package) runs `mbsync -a` every 5 minutes. This script enables it, so it must
# run AFTER install-dotfiles.sh has stowed the unit (install-all.sh orders it
# that way). Run standalone? Stow the package first.
#
# This script automates the installable parts: packages, Maildir dirs, a
# passphraseless GPG key (oama encrypts tokens to it) + pass init, and the sync
# timer. It can't do the interactive Google steps, so it finishes by listing
# them: create a Google Cloud OAuth client, write ~/.config/oama/config.yaml,
# and `oama authorize google <addr>` per account. Then `mbsync -a`.

if pacman -Qi aerc &>/dev/null && pacman -Qi isync &>/dev/null \
  && pacman -Qi msmtp &>/dev/null && pacman -Qi pass &>/dev/null; then
  echo "aerc mail stack already installed."
else
  sudo pacman -S --noconfirm --needed aerc isync msmtp pass w3m
fi

# OAuth2 token manager (oama) + the XOAUTH2 SASL plugin isync needs. Both AUR.
if pacman -Qi oama-bin &>/dev/null && pacman -Qi cyrus-sasl-xoauth2-git &>/dev/null; then
  echo "oama + cyrus-sasl-xoauth2 already installed."
else
  yay -S --noconfirm --needed oama-bin cyrus-sasl-xoauth2-git
fi

# Maildir root that mbsync syncs into and aerc reads from.
MAILDIR_ROOT="$HOME/.local/share/mail"
mkdir -p "$MAILDIR_ROOT"
echo "Maildir root ready at $MAILDIR_ROOT"

# mbsync needs each account's store directory to exist up front (it creates the
# mailbox folders inside, but not the top-level dir). Derive them from the
# stowed isyncrc so this tracks the configured accounts automatically.
if [ -f "$HOME/.config/isyncrc" ]; then
  grep -E '^Path ' "$HOME/.config/isyncrc" | awk '{print $2}' | sed "s#^~#$HOME#" \
    | while read -r p; do mkdir -p "$p"; done
fi

# ── GPG key (oama encrypts its OAuth tokens to it) ──────────────────────────
# oama keeps tokens in GPG-encrypted files; pass is also inited here in case you
# prefer to feed the OAuth client_secret from pass. The key is per-machine (never
# in dotfiles) and passphraseless by design: ~/.gnupg is already protected by
# LUKS disk encryption, and a passphrase would make the 5-min mbsync.timer pop a
# pinentry prompt. Override identity: GPG_UID="Name <addr>" ./install-aerc-mail.sh
GPG_UID="${GPG_UID:-Av <av@lab828.com>}"

if gpg --list-secret-keys "$GPG_UID" &>/dev/null; then
  echo "GPG key for $GPG_UID already present."
else
  echo "Generating passphraseless GPG key for $GPG_UID..."
  gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "$GPG_UID" default default never
fi

if [ -f "$HOME/.password-store/.gpg-id" ]; then
  echo "pass store already initialized ($(cat "$HOME/.password-store/.gpg-id"))."
else
  GPG_FPR=$(gpg --list-secret-keys --with-colons "$GPG_UID" | awk -F: '/^fpr:/{print $10; exit}')
  pass init "$GPG_FPR"
fi

# Enable the periodic sync timer if its unit has been stowed from dotfiles.
if [ -e "$HOME/.config/systemd/user/mbsync.timer" ] && command -v systemctl &>/dev/null; then
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable --now mbsync.timer 2>/dev/null || true
  echo "Enabled mbsync.timer (syncs every 5 min)."
else
  echo "mbsync.timer not found — stow the aerc-mail dotfiles package, then:"
  echo "  systemctl --user enable --now mbsync.timer"
fi

# Interactive OAuth2 steps this script can't do, plus a per-account status check.
# Accounts are derived from the stowed isyncrc so the list tracks the config.
echo
echo "OAuth2 setup (per machine, one-time):"
echo "  1. Google Cloud Console: new project -> enable Gmail API -> OAuth consent"
echo "     screen (External, PUBLISH it to avoid 7-day token expiry, scope"
echo "     https://mail.google.com/) -> Credentials -> OAuth client ID (Desktop app)."
echo "  2. oama template > ~/.config/oama/config.yaml   # set GPG key + client_id/secret"
echo "  3. Authorize each account listed below, then run 'mbsync -a' and open 'aerc'."
ISYNCRC="$HOME/.config/isyncrc"
if [ -f "$ISYNCRC" ]; then
  entries=$(grep -oE 'oama access [^"]+' "$ISYNCRC" | awk '{print $3}' | sort -u || true)
  for e in $entries; do
    if command -v oama &>/dev/null && oama access "$e" &>/dev/null; then
      echo "  [authorized] $e"
    else
      echo "  [todo]       oama authorize google $e"
    fi
  done
else
  echo "  (stow the aerc-mail dotfiles package to get the per-account list)"
fi
