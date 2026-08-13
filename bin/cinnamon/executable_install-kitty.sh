#!/usr/bin/env bash
set -euo pipefail

no_default=0
if [[ "${1:-}" == "--no-default" ]]; then
  no_default=1
fi

kitty_bin="$HOME/.local/kitty.app/bin/kitty"

echo "installing/upgrading kitty..."
curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n

[[ -x "$kitty_bin" ]] || { echo "kitty binary not found at $kitty_bin" >&2; exit 1; }

apps_dir="$HOME/.local/share/applications"
mkdir -p "$apps_dir"

icons_dir="$HOME/.local/share/icons/hicolor/256x256/apps"
mkdir -p "$icons_dir"
cp -f "$HOME/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png" "$icons_dir/"

cat > "$apps_dir/kitty.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Kitty
Icon=kitty
Exec=$kitty_bin
StartupWMClass=kitty
Terminal=false
Categories=Utility;
DESKTOP

update-desktop-database -q "$apps_dir" 2>/dev/null || true
echo "done: $apps_dir/kitty.desktop"

wrapper="$HOME/bin/kitty-nemo-wrapper"
cat > "$wrapper" << WRAPPER
#!/bin/bash
# Nemo sets cwd before spawning; \$PWD holds the target directory
exec "$kitty_bin" --directory "\$PWD"
WRAPPER
chmod +x "$wrapper"

if [[ $no_default -eq 0 ]]; then
  gsettings set org.cinnamon.desktop.default-applications.terminal exec "$wrapper"
  gsettings set org.cinnamon.desktop.default-applications.terminal exec-arg ''
  echo "default terminal set to: $wrapper"
fi
