#!/usr/bin/env bash
[[ ${XDG_CURRENT_DESKTOP:-} == *Cinnamon* ]] || { echo "$0: not Cinnamon, aborting" >&2; exit 1; }

TARGET_CLASS="vesktop.vesktop"   # WM_CLASS; title changes with the open channel
TARGET_DESKTOP=1   # wmctrl uses 0-based indexing: 1 == desktop 2
SLEEP_INTERVAL=0.3

while true; do
    # Skip the splash window (same class, title "vesktop"); the main window's title starts with "Discord"
    WIN=$(wmctrl -lx | awk -v c="$TARGET_CLASS" '$3 == c && / Discord/ {print $1; exit}')
    if [[ -n "$WIN" ]]; then
        CUR=$(wmctrl -d | awk '$2 == "*" {print $1}')
        # Vesktop starts minimized; Cinnamon only un-minimizes on a real activation
        # (wmctrl -a gets blocked by focus-stealing prevention, xdotool's isn't)
        xdotool windowactivate --sync "$WIN"
        wmctrl -i -r "$WIN" -t "$TARGET_DESKTOP"
        wmctrl -i -r "$WIN" -b add,maximized_vert,maximized_horz
        wmctrl -s "$CUR"
        echo "Found vesktop and moved it"
        sleep 5s
        # Set priority to normal
        for pid in $(pgrep -x vesktop); do
          renice 0 "$pid"
        done
        exit 0
    fi
    sleep "$SLEEP_INTERVAL"
done
