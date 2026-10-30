#!/usr/bin/env bash
[[ ${XDG_CURRENT_DESKTOP:-} == *Cinnamon* ]] || { echo "$0: not Cinnamon, aborting" >&2; exit 1; }

TARGET_CLASS="steamwebhelper.steam"   # WM_CLASS; friends/chat windows share it
TARGET_DESKTOP=3   # wmctrl uses 0-based indexing: 3 == desktop 4
SLEEP_INTERVAL=0.3

while true; do
    # Main window's title is exactly "Steam"
    WIN=$(wmctrl -lx | awk -v c="$TARGET_CLASS" '$3 == c && $5 == "Steam" && NF == 5 {print $1; exit}')
    if [[ -n "$WIN" ]] && wmctrl -i -r "$WIN" -t "$TARGET_DESKTOP"; then
        echo "Found steam and moved it"
        sleep 1s
        wmctrl -i -r "$WIN" -b add,maximized_vert,maximized_horz
        exit 0
    fi
    sleep "$SLEEP_INTERVAL"
done
