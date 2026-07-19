function _tmux_window --description 'Open a new tmux window running command, then attach'
    set -l cmd $argv[1]
    if test -z "$cmd"
        echo "Usage: _tmux_window 'command'"
        return 2
    end

    tmux new-session -d -s main 2>/dev/null; or true
    tmux new-window -t main: -c (pwd) "fish -c '$cmd; exec fish'"
    exec tmux attach-session -t main
end
