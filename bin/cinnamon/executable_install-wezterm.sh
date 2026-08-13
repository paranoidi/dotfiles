#!/usr/bin/env bash
set -euo pipefail

no_default=0
if [[ "${!#:-}" == "--no-default" ]]; then
  no_default=1
  set -- "${@:1:$(($#-1))}"
fi

if [[ $# -ne 1 || "$1" == "-h" || "$1" == "--help" ]]; then
  echo "usage: $(basename "$0") <path-to-wezterm-appimage> [--no-default]"
  echo "  installs a .desktop entry and sets wezterm as the Cinnamon default terminal"
  echo "  --no-default: skip setting as the Nemo/Cinnamon default terminal"
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

if [[ $no_default -eq 0 ]]; then
  gsettings set org.cinnamon.desktop.default-applications.terminal exec "$wrapper"
  gsettings set org.cinnamon.desktop.default-applications.terminal exec-arg ''
  echo "default terminal set to: $wrapper"
fi