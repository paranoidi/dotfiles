#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${1:-${OUTPUT_FILE:-"${SCRIPT_DIR}/resources/gnome-terminal.dconf"}}"

command -v dconf >/dev/null || { echo "dconf not found"; exit 1; }

mkdir -p "$(dirname "$OUTPUT_FILE")"
dconf dump /org/gnome/terminal/legacy/ > "$OUTPUT_FILE"

echo "Exported GNOME Terminal settings to $OUTPUT_FILE"
