function ok --description 'Send desktop notification: tmux session (if set) + pwd'
    set -l wd (string replace --regex "^$HOME" "~" (pwd))
    set -l label ok

    if set -q TMUX
        set label "tmux:"(tmux display-message -p "#{session_name}" 2>/dev/null)
    end

    toast -i ✅ "$label — $wd"
end
