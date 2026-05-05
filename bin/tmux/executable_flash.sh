#!/bin/bash
# Called by Alt key bindings to flash window titles for 3 seconds.
# Repeated presses reset the timer.

TMUX_FLASH_PIDFILE="/tmp/.tmux-flash-pid"

# Kill any previous timer so rapid presses extend the window
if [ -f "$TMUX_FLASH_PIDFILE" ]; then
    OLD_PID=$(cat "$TMUX_FLASH_PIDFILE")
    kill "$OLD_PID" 2>/dev/null
fi

tmux set -g @show_titles true
tmux refresh-client -S

# Background timer — auto-hide after 3 seconds
(sleep 3 && tmux set -g @show_titles false && tmux refresh-client -S) &
echo $! > "$TMUX_FLASH_PIDFILE"