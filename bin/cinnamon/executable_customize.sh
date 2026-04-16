#!/usr/bin/env bash
set -euo pipefail

customize_cinnamon() {
    echo "🔧 Customizing Cinnamon..."

    # How to open new windows
    gsettings set org.cinnamon.muffin placement-mode "center"

    # set screensaver to 2 minutes
    gsettings set org.cinnamon.desktop.session idle-delay 300

    # switch capslock to esc
    #setxkbmap -option caps:escape
}

# Disable Grouped Window List Super+number shortcuts (all instances)
disable_grouped_window_list_super_num() {
    echo "🔧 Disabling Grouped Window List Super+number shortcuts (all instances)..."

    # Step 1: Get all enabled applet IDs from Cinnamon
    ENABLED_APPLETS=$(dconf read /org/cinnamon/enabled-applets || echo "[]")

    # Only keep grouped-window-list applets
    # Pattern: panel:position:instance:applet-id
    GROUPED_IDS=$(echo "$ENABLED_APPLETS" | grep -oP 'grouped-window-list(@[^:]+)?' | sort -u)

    if [ -z "$GROUPED_IDS" ]; then
        echo "⚠️ No Grouped Window List applets found in enabled-applets." >&2
        return 1
    fi

    # Step 2: Possible config directories
    BASE_DIRS=(
        "$HOME/.config/cinnamon/spices"
        "$HOME/.config/cinnamon/applets"
    )

    FOUND=0

    for applet in $GROUPED_IDS; do
        for dir in "${BASE_DIRS[@]}"; do
            JSON_DIR="$dir/$applet"
            [ -d "$JSON_DIR" ] || continue

            for file in "$JSON_DIR"/*.json; do
                [ -f "$file" ] || continue
                FOUND=1
                echo "➡️ Processing $file"

                # Use jq to safely set nested value
                tmp=$(mktemp)
                if ! jq 'if .["super-num-hotkeys"] then .["super-num-hotkeys"].value = false else . end' "$file" > "$tmp"; then
                    rm -f "$tmp"
                    return 1
                fi
                mv "$tmp" "$file"
            done
        done
    done

    if [ "$FOUND" -eq 0 ]; then
        echo "❌ No config JSON files found for Grouped Window List applets." >&2
        return 1
    fi

    echo "✅ All Super+number shortcuts disabled."
    echo "ℹ️ Restart Cinnamon to apply changes."
}

install_polkit_password_rules() {
    echo "🔧 Installing password policy rules..."
    sudo cp resources/10-my.rules /etc/polkit-1/rules.d/
}

customize_cinnamon
disable_grouped_window_list_super_num
install_polkit_password_rules
