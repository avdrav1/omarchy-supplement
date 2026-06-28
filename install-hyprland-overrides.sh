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

# Ensure a per-machine monitor/scale file exists (sourced by the overrides).
# This file is intentionally NOT tracked in git; set MONSCALE per machine.
LOCAL_MONITORS="$HOME/.config/hypr/monitors.local.conf"
if [ ! -f "$LOCAL_MONITORS" ]; then
    echo "Creating $LOCAL_MONITORS from example (set MONSCALE for this machine)"
    cp "$SCRIPT_DIR/monitors.local.conf.example" "$LOCAL_MONITORS"
fi

echo "Hyprland overrides setup complete!"
