function ok --description 'Send desktop notification: tmux session (if set) + pwd'
    set -l wd (string replace --regex "^$HOME" "~" (pwd))
    set -l title ok

    if set -q TMUX
        set title tmux: (tmux display-message -p "#{session_name}" 2>/dev/null)
    end

    notify-send \
        --hint=int:transient:1 \
        --icon=utilities-terminal \
        --app-name=fish \
        --expire-time=3500 \
        "$title" "$wd"
end
