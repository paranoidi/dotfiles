#!/usr/bin/env bash
set -euo pipefail

# keyd intercepts keys before X11 — disable it if running
if systemctl is-active --quiet keyd 2>/dev/null; then
    echo "[+] Stopping keyd (conflicts with xmodmap)..."
    sudo systemctl stop keyd
    sudo systemctl disable keyd
fi

remap_key() {
    local keycode="$1"
    local mapping="$2"
    local name="$3"
    local xmodmap_file="$HOME/.xmodmaprc-${name}"
    local autostart_file="$HOME/.config/autostart/${name}-key.desktop"

    echo "[+] Applying xmodmap remap (keycode $keycode)..."
    xmodmap -e "keycode $keycode = $mapping"

    echo "[+] Writing $xmodmap_file..."
    echo "keycode $keycode = $mapping" > "$xmodmap_file"

    echo "[+] Installing Cinnamon autostart entry..."
    mkdir -p "$(dirname "$autostart_file")"
    cat > "$autostart_file" <<EOF
[Desktop Entry]
Type=Application
Name=${name^} Key Remap
Exec=bash -c "for i in 1 2 3 4 5 6; do sleep 6; xmodmap $xmodmap_file; done"
X-GNOME-Autostart-enabled=true
EOF
}

# Finnish keyboard layout fixes
# å (keycode 34) → plain slash
remap_key 34 "slash question slash question slash" "slash"

# dead_diaeresis/dead_circumflex (keycode 35) → plain tilde/caret
remap_key 35 "asciitilde asciicircum bracketright braceright asciitilde" "tilde"

echo
echo "[✓] Done. Keys remapped immediately and will persist across logins."
echo
echo "    å        → /        (shift → ?)"
echo "    dead key → ~ / ^    (shift → ^)"
echo
echo "To undo, run:"
echo "    xmodmap -e 'keycode 34 = aring Aring bracketleft braceleft dead_doubleacute dead_abovering'"
echo "    xmodmap -e 'keycode 35 = dead_diaeresis dead_circumflex'"
echo "    rm \$HOME/.xmodmaprc-{slash,tilde} \$HOME/.config/autostart/{slash,tilde}-key.desktop"
