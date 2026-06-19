#!/usr/bin/env bash
set -euo pipefail

XMODMAP_FILE="$HOME/.xmodmaprc-tilde"
AUTOSTART_FILE="$HOME/.config/autostart/tilde-key.desktop"

# Remap Finnish dead-key (keycode 35: dead_diaeresis/dead_circumflex)
# to plain tilde and caret
KEYCODE=35

# keyd intercepts keys before X11 — disable it if running
if systemctl is-active --quiet keyd 2>/dev/null; then
    echo "[+] Stopping keyd (conflicts with xmodmap)..."
    sudo systemctl stop keyd
    sudo systemctl disable keyd
fi

echo "[+] Applying xmodmap remap (keycode $KEYCODE → ~ / ^)..."
xmodmap -e "keycode $KEYCODE = asciitilde asciicircum bracketright braceright asciitilde"

echo "[+] Writing $XMODMAP_FILE..."
cat > "$XMODMAP_FILE" <<EOF
keycode $KEYCODE = asciitilde asciicircum bracketright braceright asciitilde
EOF

echo "[+] Installing Cinnamon autostart entry..."
mkdir -p "$(dirname "$AUTOSTART_FILE")"
cat > "$AUTOSTART_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Tilde Key Remap
Exec=bash -c "sleep 3 && xmodmap $XMODMAP_FILE"
X-GNOME-Autostart-enabled=true
EOF

echo
echo "[✓] Done. Key remapped immediately and will persist across logins."
echo
echo "    ]        → ~"
echo "    shift+]  → ^"
echo "    altgr+]  → ~"
echo
echo "To undo, run:"
echo "    xmodmap -e 'keycode $KEYCODE = dead_diaeresis dead_circumflex'"
echo "    rm $AUTOSTART_FILE $XMODMAP_FILE"
