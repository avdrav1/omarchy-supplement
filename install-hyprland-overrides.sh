#!/bin/bash

set -e

HYPRLAND_CONFIG="$HOME/.config/hypr/hyprland.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERRIDES_CONFIG="$SCRIPT_DIR/hyprland-overrides.conf"
SOURCE_LINE="source = $OVERRIDES_CONFIG"

# Check if hyprland config exists
if [ ! -f "$HYPRLAND_CONFIG" ]; then
    echo "Hyprland config not found at $HYPRLAND_CONFIG"
    echo "Please install hyprland first"
    exit 1
fi

# Check if overrides config exists
if [ ! -f "$OVERRIDES_CONFIG" ]; then
    echo "Overrides config not found at $OVERRIDES_CONFIG"
    exit 1
fi

# Check if source line already exists in hyprland.conf
if grep -Fxq "$SOURCE_LINE" "$HYPRLAND_CONFIG"; then
    echo "Source line already exists in $HYPRLAND_CONFIG"
else
    echo "Adding source line to $HYPRLAND_CONFIG"
    echo "" >> "$HYPRLAND_CONFIG"
    echo "$SOURCE_LINE" >> "$HYPRLAND_CONFIG"
    echo "Source line added successfully"
fi

# Select the per-machine monitor/scale file by hostname and symlink it to the
# path sourced by hyprland-overrides.conf. Per-host files live in hosts/ and
# are tracked in git; a new machine is seeded from hosts/default.conf.
LOCAL_MONITORS="$HOME/.config/hypr/monitors.local.conf"
HOST="$(hostname)"
HOSTFILE="$SCRIPT_DIR/hosts/$HOST.conf"
if [ ! -f "$HOSTFILE" ]; then
    echo "Creating hosts/$HOST.conf from default (set MONSCALE and commit it)"
    cp "$SCRIPT_DIR/hosts/default.conf" "$HOSTFILE"
fi
ln -sf "$HOSTFILE" "$LOCAL_MONITORS"

echo "Hyprland overrides setup complete!"
