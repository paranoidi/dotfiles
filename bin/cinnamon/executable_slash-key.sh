#!/usr/bin/env bash
set -euo pipefail

XMODMAP_FILE="$HOME/.xmodmaprc-slash"
AUTOSTART_FILE="$HOME/.config/autostart/slash-key.desktop"

# Remap Finnish å (keycode 34: aring/Aring) to plain slash
KEYCODE=34

# keyd intercepts keys before X11 — disable it if running
if systemctl is-active --quiet keyd 2>/dev/null; then
    echo "[+] Stopping keyd (conflicts with xmodmap)..."
    sudo systemctl stop keyd
    sudo systemctl disable keyd
fi

echo "[+] Applying xmodmap remap (keycode $KEYCODE → / / ?)..."
xmodmap -e "keycode $KEYCODE = slash question slash question slash"

echo "[+] Writing $XMODMAP_FILE..."
cat > "$XMODMAP_FILE" <<EOF
keycode $KEYCODE = slash question slash question slash
EOF

echo "[+] Installing Cinnamon autostart entry..."
mkdir -p "$(dirname "$AUTOSTART_FILE")"
cat > "$AUTOSTART_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Slash Key Remap
Exec=bash -c "sleep 3 && xmodmap $XMODMAP_FILE"
X-GNOME-Autostart-enabled=true
EOF

echo
echo "[✓] Done. Key remapped immediately and will persist across logins."
echo
echo "    å        → /"
echo "    shift+å  → ?"
echo "    altgr+å  → /"
echo
echo "To undo, run:"
echo "    xmodmap -e 'keycode $KEYCODE = aring Aring bracketleft braceleft dead_doubleacute dead_abovering'"
echo "    rm $AUTOSTART_FILE $XMODMAP_FILE"
