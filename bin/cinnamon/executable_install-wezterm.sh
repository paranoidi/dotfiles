#!/usr/bin/env bash
set -euo pipefail

appimage="$1"
[[ -f "$appimage" ]] || { echo "not found: $appimage" >&2; exit 1; }

apps_dir="$HOME/.local/share/applications"
mkdir -p "$apps_dir"

cat > "$apps_dir/wezterm.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Wezterm
Icon=Terminal
Exec=$appimage
StartupWMClass=org.wezfurlong.wezterm
Terminal=false
Categories=Utility;
DESKTOP

update-desktop-database -q "$apps_dir" 2>/dev/null || true
echo "done: $apps_dir/wezterm.desktop"