#!/bin/bash

set -euo pipefail

# Install rmpc (Rust-based MPD client with visualizer) and its core dependencies
# Arch package: rmpc (community/extra repo)
yay -S --noconfirm --needed rmpc cava

# Ensure MPD is reachable on the default localhost:6600 endpoint.
# (MPD itself is installed/configured by install-mpd.sh; this script just
# provides a gentle hint if MPD is not running.)
if ! mpc status &>/dev/null; then
  echo "Warning: MPD does not appear to be running or reachable on 127.0.0.1:6600."
  echo "Run: systemctl --user start mpd.service   (or ./install-mpd.sh)"
fi

# Bootstrap a per-user config/theme if none exist yet, without touching
# dotfiles-managed setups.
CONFIG_DIR="$HOME/.config/rmpc"
CONFIG_FILE="$CONFIG_DIR/config.ron"
THEME_FILE="$CONFIG_DIR/theme.ron"

mkdir -p "$CONFIG_DIR"

# If the user already has any rmpc config, leave everything alone.
if [ -f "$CONFIG_FILE" ] || [ -f "$THEME_FILE" ]; then
  echo "Existing rmpc config/theme detected in $CONFIG_DIR; not overwriting."
  echo "Install complete. Launch rmpc with: rmpc"
  exit 0
fi

# Create a minimal config tuned for local MPD + album art + Cava visualizer.
cat >"$CONFIG_FILE" <<'EOF'
#![enable(implicit_some)]
#![enable(unwrap_newtypes)]
#![enable(unwrap_variant_newtypes)]
(
  // MPD connection
  address: "127.0.0.1:6600",

  // Album art behaviour (Ghostty supports Kitty protocol out of the box)
  album_art: (
    method: Auto,
    // Keep HTTP(S) disabled by default; local files get art from embedded
    // metadata or cover.* files in the directory.
    disabled_protocols: ["http://", "https://"],
  ),

  // Cava visualizer configuration; reads from MPD's FIFO at /tmp/mpd.fifo
  cava: (
    framerate: 60,
    autosens: true,
    sensitivity: 100,
    input: (
      method: Fifo,
      source: "/tmp/mpd.fifo",
      sample_rate: 44100,
      channels: 2,
      sample_bits: 16,
    ),
    smoothing: (
      noise_reduction: 77,
      monstercat: false,
      waves: false,
    ),
    eq: [],
  ),

  // Tabs layout: single tab with AlbumArt + Queue + Cava stacked
  tabs: [
    (
      name: "Queue",
      pane: Split(
        direction: Horizontal,
        panes: [
          (size: "35%", pane: Pane(AlbumArt)),
          (size: "65%", pane: Split(
            direction: Vertical,
            panes: [
              (size: "60%", pane: Pane(Queue)),
              (size: "40%", pane: Pane(Cava)),
            ],
          )),
        ],
      ),
    ),
  ],
)
EOF

if command -v rmpc-theme &>/dev/null; then
  rmpc-theme >"$THEME_FILE" || true
else
  # Minimal theme; users can override via dotfiles later.
  cat >"$THEME_FILE" <<'EOF'
(
  background: "#000000",
  foreground: "#ffffff",
  accent: "#ff6ac1",
)
EOF
fi

echo "rmpc installed and initial config/theme bootstrapped in $CONFIG_DIR."
echo "Start it with: rmpc"
