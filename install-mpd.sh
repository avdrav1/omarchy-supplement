#!/bin/bash

set -euo pipefail

# Install MPD (Music Player Daemon), the mpc CLI client, and yt-dlp for YouTube support
yay -S --noconfirm --needed mpd mpc yt-dlp

# Basic user-level MPD configuration that plays well with rmpc and Omarchy setup
MPD_CONFIG_DIR="$HOME/.config/mpd"
MPD_DATA_DIR="$HOME/.local/share/mpd"
MPD_PLAYLIST_DIR="$MPD_DATA_DIR/playlists"

mkdir -p "$MPD_CONFIG_DIR" "$MPD_PLAYLIST_DIR"

MPD_CONF="$MPD_CONFIG_DIR/mpd.conf"

# Only create a config if the user (or dotfiles) hasn't provided one yet
if [ ! -f "$MPD_CONF" ]; then
  cat >"$MPD_CONF" <<'EOF'
music_directory "~/Music"
playlist_directory "~/.local/share/mpd/playlists"
db_file "~/.local/share/mpd/database"
log_file "~/.local/share/mpd/log"
pid_file "~/.local/share/mpd/pid"
state_file "~/.local/share/mpd/state"
sticker_file "~/.local/share/mpd/sticker.sql"

bind_to_address "127.0.0.1"
port "6600"

audio_output {
    type "pulse"
    name "Pulseaudio"
}

audio_output {
    type "fifo"
    name "Visualizer FIFO"
    path "/tmp/mpd.fifo"
    format "44100:16:2"
}
EOF

  echo "Created basic MPD config at $MPD_CONF (uses ~/Music and PulseAudio)."
else
  echo "MPD config already exists at $MPD_CONF, leaving it unchanged."
fi

# Try to enable user-level MPD service if systemd --user is available
if command -v systemctl &>/dev/null; then
  systemctl --user enable --now mpd.service 2>/dev/null || true
fi

# Install a small helper to make mpc play YouTube/YouTube Music URLs via yt-dlp
HELPER_DIR="$HOME/.local/bin"
HELPER_PATH="$HELPER_DIR/mpc-yt"

mkdir -p "$HELPER_DIR"

if [ ! -f "$HELPER_PATH" ]; then
  cat >"$HELPER_PATH" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: mpc-yt <youtube-or-youtube-music-url>" >&2
  exit 1
fi

URL="$1"

if ! command -v yt-dlp &>/dev/null; then
  echo "yt-dlp is required but not found in PATH." >&2
  exit 1
fi

# Resolve the direct audio stream URL from the YouTube/YouTube Music URL
STREAM_URL="$(yt-dlp -g -f bestaudio "$URL")"

if [ -z "$STREAM_URL" ]; then
  echo "Failed to resolve audio stream for $URL" >&2
  exit 1
fi

# Clear current queue, add the resolved stream, and start playback
mpc clear
mpc add "$STREAM_URL"
mpc play
EOF

  chmod +x "$HELPER_PATH"
  echo "Installed mpc-yt helper at $HELPER_PATH (uses yt-dlp to resolve YouTube/YouTube Music URLs)."
else
  echo "mpc-yt helper already exists at $HELPER_PATH, leaving it unchanged."
fi

echo "MPD installation, basic configuration, and YouTube helper setup complete."
