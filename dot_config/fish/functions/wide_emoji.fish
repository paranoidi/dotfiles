function wide_emoji --description '🧰 Print emoji with terminal-adjusted spacing (1 space in tmux, 2 elsewhere)'
    if set -q argv[1]
        if set -q TMUX
            echo -n "$argv[1] "
        else
            echo -n "$argv[1]  "
        end
    end
end