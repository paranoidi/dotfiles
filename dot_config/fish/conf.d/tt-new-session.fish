# Show session name when fish starts in a new tmux session created by tt.
# TT_NEW_SESSION_NAME is set via `tmux setenv` in tt.fish — no tmux calls needed here.
if set -q TT_NEW_SESSION_NAME
    echo "New session: $TT_NEW_SESSION_NAME"
    set -e TT_NEW_SESSION_NAME
    # Remove from tmux env so subsequent panes in this session don't repeat it
    command tmux setenv -r TT_NEW_SESSION_NAME 2>/dev/null
end
