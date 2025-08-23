#!/usr/bin/env bash
set -euo pipefail

: "${OUTPUT_FILE:=gnome-terminal-colors.json}"

# Tools check
command -v gsettings >/dev/null || { echo "gsettings not found"; exit 1; }
command -v jq >/dev/null || { echo "jq not found (sudo apt install jq)"; exit 1; }

# Resolve default profile
PROFILE_ID=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d \')
PROFILE_PATH="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${PROFILE_ID}/"

# Read values from gsettings (they come with single quotes; strip them for JSON)
BG=$(gsettings get "$PROFILE_PATH" background-color | tr -d "'")
FG=$(gsettings get "$PROFILE_PATH" foreground-color | tr -d "'")
BOLD=$(gsettings get "$PROFILE_PATH" bold-color | tr -d "'")

# Palette comes like: ['#000000', '#ff0000', ...]
PALETTE_GSET=$(gsettings get "$PROFILE_PATH" palette)

# Convert to JSON array by switching single quotes -> double quotes
PALETTE_JSON=$(printf "%s" "$PALETTE_GSET" | sed "s/'/\"/g")

# Build JSON safely with jq
jq -n \
  --arg bg "$BG" \
  --arg fg "$FG" \
  --arg bold "$BOLD" \
  --argjson palette "$PALETTE_JSON" \
  '{background:$bg, foreground:$fg, bold:$bold, palette:$palette}' \
  > "$OUTPUT_FILE"

echo "Exported GNOME Terminal colors to $OUTPUT_FILE"
