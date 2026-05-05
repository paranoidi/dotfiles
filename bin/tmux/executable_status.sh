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

# Count total windows — collapse to emoji when count exceeds threshold
# Threshold scales with terminal width to avoid status bar overflow.
TOTAL_WINDOWS=$(tmux display-message -p '#{session_windows}' 2>/dev/null)
WINDOW_WIDTH=$(tmux display-message -p '#{window_width}' 2>/dev/null)
: "${WINDOW_WIDTH:=80}"

# Scale threshold with terminal width: ~1 per 18 cols, min 3, max 10
# Gentler slope than previous formula: less aggressive on large widths,
# more aggressive on smaller widths.
#THRESHOLD=$(( WINDOW_WIDTH / 16 ))
#if [ "$THRESHOLD" -lt 3 ]; then THRESHOLD=3; fi
#if [ "$THRESHOLD" -gt 10 ]; then THRESHOLD=10; fi

# Alternative:
# Map width to threshold: wider terminal = more room for full entries
if   [ "$WINDOW_WIDTH" -ge 180 ]; then THRESHOLD=11
elif [ "$WINDOW_WIDTH" -ge 170 ]; then THRESHOLD=10
elif [ "$WINDOW_WIDTH" -ge 160 ]; then THRESHOLD=9
elif [ "$WINDOW_WIDTH" -ge 150 ]; then THRESHOLD=8
elif [ "$WINDOW_WIDTH" -ge 140 ]; then THRESHOLD=7
elif [ "$WINDOW_WIDTH" -ge 120 ]; then THRESHOLD=6
elif [ "$WINDOW_WIDTH" -ge 100 ]; then THRESHOLD=5
elif [ "$WINDOW_WIDTH" -ge 90  ]; then THRESHOLD=5
else                                   THRESHOLD=5
fi

if [ "$TOTAL_WINDOWS" -ge "$THRESHOLD" ]; then
    # Hidden — show just the emoji icon
    ICON="$(printf '%s' "$FULL" | awk '{print $1}')"
    printf '%s' "$ICON"
else
    # Few windows — show full info
    printf '%s' "$FULL"
fi
