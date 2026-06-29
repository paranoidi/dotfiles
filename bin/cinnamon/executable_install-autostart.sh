#!/usr/bin/env bash
# Sets up ~/bin/autostart to run at login via ~/.config/autostart/bin-autostart.desktop

set -euo pipefail

AUTOSTART_SH="$HOME/bin/autostart.sh"
AUTOSTART_DIR="$HOME/bin/autostart"
DESKTOP_DIR="$HOME/.config/autostart"
DESKTOP_FILE="$DESKTOP_DIR/bin-autostart.desktop"

echo "==> Checking ~/bin/autostart.sh..."
if [[ ! -f "$AUTOSTART_SH" ]]; then
    echo "ERROR: $AUTOSTART_SH not found."
    exit 1
fi
chmod +x "$AUTOSTART_SH"
echo "  Executable: $AUTOSTART_SH"

echo "==> Making scripts in ~/bin/autostart/ executable..."
if [[ ! -d "$AUTOSTART_DIR" ]]; then
    echo "ERROR: $AUTOSTART_DIR not found."
    exit 1
fi
count=0
while IFS= read -r -d '' f; do
    chmod +x "$f"
    echo "  Executable: $f"
    ((count++)) || true
done < <(find "$AUTOSTART_DIR" -maxdepth 1 -type f -print0)
echo "  $count script(s) marked executable."

echo "==> Installing desktop autostart entry..."
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Exec=$AUTOSTART_SH
X-GNOME-Autostart-enabled=true
NoDisplay=false
Hidden=false
Name[en_US]=Execute bin/autostart scripts
Comment[en_US]=No description
X-GNOME-Autostart-Delay=0
EOF
echo "  Written: $DESKTOP_FILE"

echo ""
echo "===== Done ====="
echo "~/bin/autostart scripts will run at next login."
echo "To test now: bash $AUTOSTART_SH"
