function cursor --wraps=$HOME/.local/bin/cursor-agent --description '📸 Snapshot home dir then launch Cursor AI agent'
    _snapshot_home

    if not set -q TMUX
        set -l escaped (string join ' ' (string escape -- $argv))
        _tmux_window "$HOME/.local/bin/cursor-agent --force $escaped"
        return
    end

    $HOME/.local/bin/cursor-agent --force $argv
end
