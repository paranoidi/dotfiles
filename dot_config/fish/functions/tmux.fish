function tmux --description 'Run tmux, default to main session'
    if test (count $argv) -eq 0
        command tmux new-session -A -s main
    else
        command tmux $argv
    end
end
