#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage: $(basename "$0") <path-to-wezterm-appimage>"
  echo "  installs a .desktop entry and sets wezterm as the Cinnamon default terminal"
  exit 1
fi

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

wrapper="$HOME/bin/wezterm-nemo-wrapper"
cat > "$wrapper" << WRAPPER
#!/bin/bash
# Nemo sets cwd before spawning; \$PWD holds the target directory
exec "$appimage" start --no-auto-connect --cwd "\$PWD"
WRAPPER
chmod +x "$wrapper"

gsettings set org.cinnamon.desktop.default-applications.terminal exec "$wrapper"
gsettings set org.cinnamon.desktop.default-applications.terminal exec-arg ''
echo "default terminal set to: $wrapper"