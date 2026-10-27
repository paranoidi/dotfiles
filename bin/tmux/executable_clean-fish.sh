#!/bin/bash
# Kill idle fish panes that share a directory with another idle fish pane.
# Usage: clean-fish.sh [current_pane_id]  (the current pane is always the one kept for its dir)

cur="$1"
declare -A seen
n=0

# Current pane first so it wins its directory; the rest in window/pane order.
panes=$(tmux list-panes -a -F '#{pane_id} #{pane_current_command} #{pane_current_path}')
ordered=$( { grep "^$cur " <<<"$panes"; grep -v "^$cur " <<<"$panes"; } )

while IFS=' ' read -r id cmd path; do
    [ "$cmd" = fish ] || continue
    if [ -n "${seen[$path]}" ]; then
        tmux kill-pane -t "$id" && n=$((n + 1))
    else
        seen[$path]=1
    fi
done <<<"$ordered"

tmux display-message "Closed $n idle fish pane(s)"
