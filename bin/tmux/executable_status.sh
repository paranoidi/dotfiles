#!/bin/bash
# Conditional window status for non-current windows.
# Shows full info if:
#   - titles are in flash mode (Alt key recently pressed), OR
#   - this window is within ±2 of the active window
# Otherwise shows just the emoji icon (first field from windows-status.sh).
#
# Usage:
#   ~/bin/tmux/status.sh <window_index> <cmd> <title> <path>

THIS_INDEX="$1"
CMD="$2"
TITLE="$3"
PATH_ARG="$4"

SHOW_TITLES=$(tmux show -v -g @show_titles 2>/dev/null)
FULL=$(~/bin/tmux/windows-status.sh "$CMD" "$TITLE" "$PATH_ARG")

# Flash mode active — show everything
if [ "$SHOW_TITLES" = "true" ]; then
    printf '%s' "$FULL"
    exit
fi

# Always show within ±2 of the active window
CURRENT_INDEX=$(tmux display-message -p '#{window_index}' 2>/dev/null)
if [ -n "$CURRENT_INDEX" ] && [ -n "$THIS_INDEX" ]; then
    DIFF=$((THIS_INDEX - CURRENT_INDEX))
    ABS_DIFF=${DIFF#-}
    if [ "$ABS_DIFF" -le 2 ]; then
        printf '%s' "$FULL"
        exit
    fi
fi

# Hidden — show just the emoji icon (first field from the full status)
ICON="$(printf '%s' "$FULL" | awk '{print $1}')"
printf '%s' "$ICON"