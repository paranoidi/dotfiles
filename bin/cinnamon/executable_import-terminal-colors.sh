#!/usr/bin/env bash
set -euo pipefail

INPUT_FILE="${1:-gnome-terminal-colors.json}"

# Tools check
command -v gsettings >/dev/null || { echo "gsettings not found"; exit 1; }
command -v jq >/dev/null || { echo "jq not found (sudo apt install jq)"; exit 1; }

# Validate JSON early
jq empty "$INPUT_FILE" || { echo "Invalid JSON in $INPUT_FILE"; exit 1; }

# Resolve default profile
PROFILE_ID=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d \')
PROFILE_PATH="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${PROFILE_ID}/"

# Read hex strings from JSON
BG=$(jq -r '.background' "$INPUT_FILE")
FG=$(jq -r '.foreground' "$INPUT_FILE")
BOLD=$(jq -r '.bold' "$INPUT_FILE")

# Read palette JSON array as compact string: ["#rrggbb", ...]
PALETTE_JSON=$(jq -c '.palette' "$INPUT_FILE")

# Convert JSON array -> GSettings variant array by changing " to '
# Result: ['#rrggbb', ...]
PALETTE_GSET=$(printf "%s" "$PALETTE_JSON" | sed 's/"/'\''/g')

# Apply
gsettings set "$PROFILE_PATH" background-color "$BG"
gsettings set "$PROFILE_PATH" foreground-color "$FG"
gsettings set "$PROFILE_PATH" bold-color "$BOLD"
gsettings set "$PROFILE_PATH" bold-color-same-as-fg true
gsettings set "$PROFILE_PATH" use-theme-colors false
gsettings set "$PROFILE_PATH" palette "$PALETTE_GSET"

echo "Imported GNOME Terminal colors from $INPUT_FILE"
