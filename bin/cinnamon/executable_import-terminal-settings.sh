#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT_FILE="${1:-${INPUT_FILE:-"${SCRIPT_DIR}/resources/gnome-terminal.dconf"}}"

command -v dconf >/dev/null || { echo "dconf not found"; exit 1; }
[[ -r "$INPUT_FILE" ]] || { echo "GNOME Terminal settings file not readable: $INPUT_FILE"; exit 1; }
[[ -s "$INPUT_FILE" ]] || { echo "GNOME Terminal settings file is empty: $INPUT_FILE"; exit 1; }

dconf load /org/gnome/terminal/legacy/ < "$INPUT_FILE"

echo "Imported GNOME Terminal settings from $INPUT_FILE"
