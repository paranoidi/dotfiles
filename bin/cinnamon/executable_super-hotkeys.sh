#!/usr/bin/env bash
set -euo pipefail

echo "Disabling Grouped Window List Super+number shortcuts (all instances)..."

# Step 1: Get all enabled applet IDs from Cinnamon
ENABLED_APPLETS=$(dconf read /org/cinnamon/enabled-applets || echo "[]")

# Only keep grouped-window-list applets
# Pattern: panel:position:instance:applet-id
GROUPED_IDS=$(echo "$ENABLED_APPLETS" | grep -oP 'grouped-window-list(@[^:]+)?' | sort -u)

if [ -z "$GROUPED_IDS" ]; then
    echo "No Grouped Window List applets found in enabled-applets."
    exit 0
fi

# Step 2: Possible config directories
BASE_DIRS=(
    "$HOME/.config/cinnamon/spices"
    "$HOME/.config/cinnamon/applets"
)

FOUND=0

for applet in $GROUPED_IDS; do
    for dir in "${BASE_DIRS[@]}"; do
        JSON_DIR="$dir/$applet"
        [ -d "$JSON_DIR" ] || continue

        for file in "$JSON_DIR"/*.json; do
            [ -f "$file" ] || continue
            FOUND=1
            echo "Processing $file"

            # Use jq to safely set nested value
            tmp=$(mktemp)
            jq 'if .["super-num-hotkeys"] then .["super-num-hotkeys"].value = false else . end' "$file" > "$tmp" && mv "$tmp" "$file"
        done
    done
done

if [ "$FOUND" -eq 0 ]; then
    echo "No config JSON files found for Grouped Window List applets."
    exit 0
fi

echo "All Super+number shortcuts disabled."
echo "Restart Cinnamon to apply changes (Alt+F2 → r on X11, or log out/in on Wayland)."
