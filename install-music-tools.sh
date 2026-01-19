#!/bin/bash

set -euo pipefail

# Install music browsing and download tools (yt-search, spot-dl, music-search)
# Requires: install-mpd.sh to have run first for MPD integration

# Install fzf if not present (needed for interactive selection)
if ! command -v fzf &>/dev/null; then
  yay -S --noconfirm --needed fzf
fi

# Install spotdl via uv for Spotify downloads
if ! command -v spotdl &>/dev/null; then
  if command -v uv &>/dev/null; then
    uv tool install spotdl
    echo "Installed spotdl via uv"
  else
    echo "Warning: uv not found, skipping spotdl installation"
    echo "Install uv first, then run: uv tool install spotdl"
  fi
else
  echo "spotdl already installed"
fi

# Create scripts directory
SCRIPT_DIR="$HOME/.local/bin"
mkdir -p "$SCRIPT_DIR"

# ---- yt-search: Interactive YouTube search with fzf ----
YT_SEARCH="$SCRIPT_DIR/yt-search"
cat >"$YT_SEARCH" <<'SCRIPT'
#!/usr/bin/env bash
# yt-search - Interactive YouTube search with fzf
# Usage: yt-search [--queue|-q] <search query>

set -euo pipefail

MUSIC_DIR="${MUSIC_DIR:-$HOME/Music}"
NUM_RESULTS="${YT_SEARCH_RESULTS:-30}"

usage() {
  echo "Usage: yt-search [--queue|-q] <search query>"
  echo "  -q, --queue   Queue tracks in MPD after download"
  echo ""
  echo "Controls:"
  echo "  TAB       Multi-select tracks"
  echo "  ENTER     Download selected"
  echo "  Ctrl-A    Select all"
  echo "  ESC       Cancel"
}

queue_after=false

# Parse flags
while [[ "${1:-}" == -* ]]; do
  case "$1" in
    -q|--queue) queue_after=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

query="$*"

if [[ -z "$query" ]]; then
  echo -n "Search YouTube: "
  read -r query
fi

if [[ -z "$query" ]]; then
  echo "No search query provided" >&2
  exit 1
fi

# Check dependencies
for cmd in yt-dlp fzf; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "yt-search: $cmd not found on PATH" >&2
    exit 1
  fi
done

echo "Searching YouTube for: $query"

# Search YouTube and format for fzf
# Format: ID | Title | Channel | Duration
selection=$(yt-dlp "ytsearch${NUM_RESULTS}:${query}" \
  --flat-playlist \
  --print "%(id)s | %(title).60s | %(channel).20s | %(duration_string)s" \
  2>/dev/null | \
  fzf --multi \
      --delimiter=' \| ' \
      --with-nth=2,3,4 \
      --header="Select tracks (TAB to multi-select, ENTER to download)" \
      --preview='vid={1}; curl -s "https://img.youtube.com/vi/${vid}/mqdefault.jpg" | chafa -s 40x20 - 2>/dev/null; echo; echo "https://youtube.com/watch?v=${vid}"' \
      --preview-window=right:45 \
      --bind='ctrl-a:select-all' \
      --height=90% \
      --border=rounded \
      --prompt="YouTube> " || true)

[[ -z "$selection" ]] && exit 0

# Extract video IDs and download each
count=0
failed=0

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  # Extract video ID (everything before first " | ")
  vid_id="${line%% | *}"
  # Extract title (between first and second " | ")
  title="${line#* | }"
  title="${title%% | *}"

  url="https://youtube.com/watch?v=${vid_id}"
  echo "Downloading: ${title}..."

  if yt-dlp \
    -x \
    --audio-format mp3 \
    --audio-quality 0 \
    --add-metadata \
    --embed-thumbnail \
    -o "$MUSIC_DIR/%(artist,channel)s/%(album,title)s/%(track_number,1)02d - %(title)s.%(ext)s" \
    "$url"; then
    count=$((count + 1))
  else
    echo "Failed: ${title}" >&2
    failed=$((failed + 1))
  fi
done <<< "$selection"

# Update MPD database
if command -v mpc &>/dev/null && [[ $count -gt 0 ]]; then
  echo "Updating MPD database..."
  mpc update --wait

  if [[ "$queue_after" == true ]]; then
    echo "Queueing recently added tracks..."
    while IFS= read -r -d '' file; do
      rel_path="${file#$HOME/Music/}"
      mpc add "$rel_path" 2>/dev/null || true
    done < <(find "$MUSIC_DIR" -type f \( -name "*.mp3" -o -name "*.opus" -o -name "*.m4a" \) -mmin -2 -print0)
  fi
fi

echo "Downloaded: ${count} track(s)"
[[ $failed -gt 0 ]] && echo "Failed: ${failed} track(s)" >&2

exit 0
SCRIPT
chmod +x "$YT_SEARCH"
echo "Installed yt-search at $YT_SEARCH"

# ---- spot-dl: Spotify download wrapper ----
SPOT_DL="$SCRIPT_DIR/spot-dl"
cat >"$SPOT_DL" <<'SCRIPT'
#!/usr/bin/env bash
# spot-dl - Download from Spotify URLs (tracks, albums, playlists)
# Usage: spot-dl [--queue|-q] <spotify-url>

set -euo pipefail

MUSIC_DIR="${MUSIC_DIR:-$HOME/Music}"

usage() {
  echo "Usage: spot-dl [--queue|-q] <spotify-url>"
  echo "  -q, --queue   Queue tracks in MPD after download"
  echo ""
  echo "Supports: track, album, playlist, artist URLs"
  echo ""
  echo "Examples:"
  echo "  spot-dl https://open.spotify.com/track/..."
  echo "  spot-dl https://open.spotify.com/album/..."
  echo "  spot-dl https://open.spotify.com/playlist/..."
  echo "  spot-dl --queue https://open.spotify.com/track/..."
}

if ! command -v spotdl &>/dev/null; then
  echo "spotdl not found. Install with: uv tool install spotdl" >&2
  exit 1
fi

queue_after=false

# Parse flags
while [[ "${1:-}" == -* ]]; do
  case "$1" in
    -q|--queue) queue_after=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

url="${1:-}"

if [[ -z "$url" ]]; then
  echo "Paste Spotify URL (track, album, or playlist):"
  read -r url
fi

if [[ -z "$url" ]]; then
  echo "No URL provided" >&2
  exit 1
fi

# Validate it looks like a Spotify URL
if [[ ! "$url" =~ ^https://open\.spotify\.com/ ]]; then
  echo "Invalid Spotify URL: $url" >&2
  echo "URL should start with: https://open.spotify.com/" >&2
  exit 1
fi

mkdir -p "$MUSIC_DIR"

echo "Downloading from Spotify: $url"

# Download with spotdl, organized by artist/album
# --user-auth uses OAuth to avoid rate limits (opens browser on first use)
spotdl download "$url" \
  --user-auth \
  --output "$MUSIC_DIR/{artist}/{album}/{track-number} - {title}.{output-ext}" \
  --format mp3 \
  --bitrate 320k

exit_code=$?

if [[ $exit_code -eq 0 ]] && command -v mpc &>/dev/null; then
  echo "Updating MPD database..."
  mpc update --wait

  if [[ "$queue_after" == true ]]; then
    echo "Queueing recently added tracks..."
    while IFS= read -r -d '' file; do
      rel_path="${file#$HOME/Music/}"
      mpc add "$rel_path" 2>/dev/null || true
    done < <(find "$MUSIC_DIR" -type f \( -name "*.mp3" -o -name "*.opus" \) -mmin -2 -print0)
  fi
fi

exit $exit_code
SCRIPT
chmod +x "$SPOT_DL"
echo "Installed spot-dl at $SPOT_DL"

# ---- music-search: Unified interface ----
MUSIC_SEARCH="$SCRIPT_DIR/music-search"
cat >"$MUSIC_SEARCH" <<'SCRIPT'
#!/usr/bin/env bash
# music-search - Unified music search interface for YouTube and Spotify
# Usage: music-search [-y|-s] [-q] [query]

set -euo pipefail

usage() {
  echo "Usage: music-search [-y|-s] [-q] [query]"
  echo "  -y, --youtube  Search YouTube directly"
  echo "  -s, --spotify  Prompt for Spotify URL"
  echo "  -q, --queue    Queue tracks after download"
  echo ""
  echo "Without flags: prompts for source selection"
}

source=""
queue_flag=""

# Parse flags
while [[ "${1:-}" == -* ]]; do
  case "$1" in
    -y|--youtube) source="youtube"; shift ;;
    -s|--spotify) source="spotify"; shift ;;
    -q|--queue) queue_flag="--queue"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

query="$*"

# Check fzf is available
if ! command -v fzf &>/dev/null; then
  echo "music-search: fzf not found on PATH" >&2
  exit 1
fi

# If no source specified, prompt with fzf
if [[ -z "$source" ]]; then
  source=$(printf "youtube\nspotify" | fzf --prompt="Source> " --height=10% --border=rounded || true)
  [[ -z "$source" ]] && exit 0
fi

case "$source" in
  youtube)
    if [[ -n "$queue_flag" ]]; then
      exec yt-search --queue "$query"
    else
      exec yt-search "$query"
    fi
    ;;
  spotify)
    if [[ -n "$queue_flag" ]]; then
      exec spot-dl --queue
    else
      exec spot-dl
    fi
    ;;
  *)
    echo "Unknown source: $source" >&2
    exit 1
    ;;
esac
SCRIPT
chmod +x "$MUSIC_SEARCH"
echo "Installed music-search at $MUSIC_SEARCH"

# ---- ncmpcpp-album-art: Display album art for ncmpcpp ----
ALBUM_ART="$SCRIPT_DIR/ncmpcpp-album-art"
cat >"$ALBUM_ART" <<'SCRIPT'
#!/usr/bin/env bash
# Display album art for currently playing MPD track
# Updates whenever the song changes

MUSIC_DIR="${HOME}/Music"

display_art() {
  clear

  # Get current song file path
  current_song=$(mpc current -f "%file%" 2>/dev/null)

  if [[ -z "$current_song" ]]; then
    echo "No song playing"
    return
  fi

  song_dir="${MUSIC_DIR}/$(dirname "$current_song")"
  song_path="${MUSIC_DIR}/${current_song}"

  # Try to extract embedded art first
  if command -v ffmpeg &>/dev/null && [[ -f "$song_path" ]]; then
    tmp_art="/tmp/ncmpcpp_art.jpg"
    if ffmpeg -y -i "$song_path" -an -vcodec copy "$tmp_art" 2>/dev/null; then
      if [[ -f "$tmp_art" && -s "$tmp_art" ]]; then
        chafa -s 40x40 --center on "$tmp_art" 2>/dev/null
        echo ""
        mpc current 2>/dev/null
        return
      fi
    fi
  fi

  # Look for cover art files in song directory
  for cover in "$song_dir"/{cover,folder,album,art,front}.{jpg,jpeg,png,webp} "$song_dir"/*.{jpg,jpeg,png,webp}; do
    if [[ -f "$cover" ]]; then
      chafa -s 40x40 --center on "$cover" 2>/dev/null
      echo ""
      mpc current 2>/dev/null
      return
    fi
  done

  # No art found
  echo "No album art"
  echo ""
  mpc current 2>/dev/null
}

# Initial display
display_art

# Watch for song changes
while true; do
  mpc idle player 2>/dev/null
  display_art
done
SCRIPT
chmod +x "$ALBUM_ART"
echo "Installed ncmpcpp-album-art at $ALBUM_ART"

# ---- ncmpcpp configuration ----
NCMPCPP_DIR="$HOME/.config/ncmpcpp"
mkdir -p "$NCMPCPP_DIR"

if [ ! -f "$NCMPCPP_DIR/config" ]; then
cat >"$NCMPCPP_DIR/config" <<'CONF'
# ncmpcpp configuration
mpd_host = "127.0.0.1"
mpd_port = 6600
mpd_music_dir = "~/Music"

# Visualizer settings
visualizer_data_source = "/tmp/mpd.fifo"
visualizer_output_name = "Visualizer FIFO"
visualizer_in_stereo = "yes"
visualizer_type = "spectrum"
visualizer_look = "●▮"
visualizer_color = "blue, cyan, green, yellow, magenta, red"

# UI settings
user_interface = "alternative"
playlist_display_mode = "columns"
browser_display_mode = "columns"
progressbar_look = "─░─"
song_status_format = "{%a - }{%t}|{%f}"
mouse_support = "yes"
startup_screen = "playlist"
CONF
echo "Created ncmpcpp config at $NCMPCPP_DIR/config"
fi

if [ ! -f "$NCMPCPP_DIR/bindings" ]; then
cat >"$NCMPCPP_DIR/bindings" <<'BIND'
def_key "up"
  scroll_up
def_key "down"
  scroll_down
def_key "left"
  previous_column
def_key "left"
  master_screen
def_key "left"
  volume_down
def_key "right"
  next_column
def_key "right"
  slave_screen
def_key "right"
  volume_up
def_key "j"
  scroll_down
def_key "k"
  scroll_up
def_key "h"
  previous_column
def_key "l"
  next_column
def_key "l"
  enter_directory
def_key "l"
  play_item
def_key "enter"
  enter_directory
def_key "enter"
  play_item
def_key "p"
  pause
def_key "s"
  stop
def_key ">"
  next
def_key "<"
  previous
def_key "space"
  add_item_to_playlist
def_key "d"
  delete_playlist_items
def_key "c"
  clear_playlist
def_key "u"
  update_database
def_key "1"
  show_playlist
def_key "2"
  show_browser
def_key "3"
  show_search_engine
def_key "4"
  show_media_library
def_key "8"
  show_visualizer
def_key "q"
  quit
BIND
echo "Created ncmpcpp bindings at $NCMPCPP_DIR/bindings"
fi

# ---- Create zsh music functions file ----
# This provides helper functions that can be sourced by zshrc
MUSIC_FUNCS="$HOME/.config/zsh/music-functions.zsh"
mkdir -p "$(dirname "$MUSIC_FUNCS")"

cat >"$MUSIC_FUNCS" <<'FUNCS'
# Music helper functions for zsh
# Source this file in your .zshrc: source ~/.config/zsh/music-functions.zsh

# Download audio from YouTube into $MUSIC_DIR (default: ~/Music), then update MPD.
yt-music() {
  if [ -z "$1" ]; then
    echo "usage: yt-music <youtube-url>"
    return 1
  fi

  local url="$1"
  local MUSIC_DIR
  MUSIC_DIR="${MUSIC_DIR:-$HOME/Music}"

  mkdir -p "$MUSIC_DIR" || return 1

  if ! command -v yt-dlp >/dev/null 2>&1; then
    echo "yt-music: yt-dlp not found on PATH (install it with your package manager)"
    return 1
  fi

  # Extract best available audio with metadata, organized by artist/album
  yt-dlp \
    --yes-playlist \
    -x \
    --audio-format mp3 \
    --audio-quality 0 \
    --add-metadata \
    --embed-thumbnail \
    -o "$MUSIC_DIR/%(artist,channel)s/%(album,playlist,title)s/%(track_number,playlist_index,1)02d - %(title)s.%(ext)s" \
    "$url"

  local exit_code=$?

  # Auto-update MPD if download succeeded
  if [ $exit_code -eq 0 ] && command -v mpc >/dev/null 2>&1; then
    echo "Updating MPD database..."
    mpc update >/dev/null 2>&1 &
  fi

  return $exit_code
}

# Update MPD database and show recent additions
mpd-refresh() {
  if ! command -v mpc >/dev/null 2>&1; then
    echo "mpd-refresh: mpc not found on PATH"
    return 1
  fi
  echo "Updating MPD database..."
  mpc update --wait
  echo "Database updated. Recent additions:"
  mpc listall | tail -10
}

# Search local MPD library with fzf and queue selected tracks
mpd-queue-search() {
  if ! command -v mpc >/dev/null 2>&1; then
    echo "mpd-queue-search: mpc not found on PATH"
    return 1
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    echo "mpd-queue-search: fzf not found on PATH"
    return 1
  fi

  local query="$*"
  local tracks

  if [ -n "$query" ]; then
    tracks=$(mpc search any "$query")
  else
    tracks=$(mpc listall)
  fi

  if [ -z "$tracks" ]; then
    echo "No tracks found"
    return 0
  fi

  echo "$tracks" | fzf --multi --header="Select tracks to queue (TAB to multi-select)" | while read -r track; do
    mpc add "$track"
    echo "Queued: $track"
  done
}

# Start ncmpcpp music player with visualizer and album art
music-session() {
  if ! command -v ncmpcpp >/dev/null 2>&1; then
    echo "music-session: ncmpcpp not found on PATH"
    return 1
  fi
  if ! command -v tmux >/dev/null 2>&1; then
    echo "music-session: tmux not found, running ncmpcpp without album art"
    ncmpcpp --screen visualizer
    return
  fi

  local session_name="music"

  # Kill existing session if any
  tmux kill-session -t "$session_name" 2>/dev/null

  # Create session with ncmpcpp (visualizer screen)
  tmux new-session -d -s "$session_name" -x "$(tput cols)" -y "$(tput lines)" 'ncmpcpp --screen visualizer'

  # Enable passthrough for Kitty graphics protocol (album art)
  tmux set -t "$session_name" allow-passthrough on

  # Split left pane for album art (30% width)
  tmux split-window -h -b -l 30% -t "$session_name" 'ncmpcpp-album-art'

  # Focus on ncmpcpp pane (right side)
  tmux select-pane -R -t "$session_name"

  # Attach
  tmux attach-session -t "$session_name"
}
FUNCS
echo "Created music functions at $MUSIC_FUNCS"

# Add source line to .zshrc if not already present
ZSHRC="$HOME/.zshrc"
SOURCE_LINE='[ -f "$HOME/.config/zsh/music-functions.zsh" ] && source "$HOME/.config/zsh/music-functions.zsh"'

if [ -f "$ZSHRC" ]; then
  if ! grep -qF "music-functions.zsh" "$ZSHRC"; then
    echo "" >> "$ZSHRC"
    echo "# Music helper functions" >> "$ZSHRC"
    echo "$SOURCE_LINE" >> "$ZSHRC"
    echo "Added music-functions.zsh source line to $ZSHRC"
  else
    echo "music-functions.zsh already sourced in $ZSHRC"
  fi
fi

echo ""
echo "Music tools installation complete!"
echo ""
echo "Available commands:"
echo "  music-session         - Launch rmpc music player"
echo "  yt-search <query>     - Interactive YouTube search with fzf"
echo "  spot-dl <url>         - Download from Spotify URLs"
echo "  music-search          - Unified interface (prompts for source)"
echo "  yt-music <url>        - Direct YouTube download"
echo "  mpd-refresh           - Update MPD database"
echo "  mpd-queue-search      - Search and queue from local library"
echo ""
echo "All commands support --queue flag to auto-queue in MPD after download."
