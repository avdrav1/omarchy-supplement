#!/bin/bash

set -euo pipefail

# Capture the live Shibumi settings into shibumi/settings.json so the next
# fresh install (install-shibumi.sh) restores them. Run this after changing
# anything in Shibumi's control center, then commit the result.
#
# Saves the State plugin's `shibumi` object from ~/.config/omarchy/shell.json,
# plus every non-Shibumi widget currently on the bar (per section), since the
# suite's install lays out only its own widgets.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_JSON="$HOME/.config/omarchy/shell.json"
OUT="$SCRIPT_DIR/shibumi/settings.json"

jq -e '.plugins[]? | select(.id == "hancore.shibumi.state") | .shibumi' "$SHELL_JSON" >/dev/null || {
  echo "ERROR: no Shibumi State settings in $SHELL_JSON -- is Shibumi installed?" >&2
  exit 1
}

mkdir -p "$(dirname "$OUT")"
jq '{
  state: (.plugins[] | select(.id == "hancore.shibumi.state") | .shibumi),
  barWidgets: (.bar.layout | with_entries(
    .value |= map(select(.id | startswith("hancore.shibumi") | not))
  ) | with_entries(select(.value | length > 0)))
}' "$SHELL_JSON" >"$OUT"

echo "Saved Shibumi settings to $OUT"
git -C "$SCRIPT_DIR" --no-pager diff --stat -- "$OUT" 2>/dev/null || true
