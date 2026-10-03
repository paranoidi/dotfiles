#!/usr/bin/env bash
# Move all WezTerm windows to workspace 1 whenever workspace 1 is entered.
CLASS="org.wezfurlong.wezterm.org.wezfurlong.wezterm"
xprop -root -spy _NET_CURRENT_DESKTOP | while read -r line; do
    [[ ${line##* } == 0 ]] || continue
    wmctrl -lx | awk -v c="$CLASS" '$3 == c && $2 != 0 && $2 != -1 {print $1}' |
        xargs -r -I{} wmctrl -i -r {} -t 0
done
