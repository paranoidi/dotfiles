function fzf_kill_process
    set -l selected (
        command ps -A -opid,user,command | \
        awk 'NR == 1 || $0 !~ /^[[:space:]]*[0-9]+[[:space:]]+[^[:space:]]+[[:space:]]+\[.*\]$/' | \
        _fzf_wrapper --multi \
                    --prompt="Kill process> " \
                    --ansi \
                    --header-lines=1 \
                    --preview="command ps -o pid,ppid=PARENT,user,%cpu,rss=RSS_IN_KB,start=START_TIME,command -p {1} || echo 'Cannot preview {1} because it exited.'" \
                    --preview-window="bottom:4:wrap" \
                    $fzf_processes_opts
    )

    if test $status -eq 0
        set -l pids
        for process in $selected
            set --append pids (string split --no-empty --field=1 -- " " $process)
        end

        if test (count $pids) -gt 0
            set -l valid_pids
            for pid in $pids
                if string match --quiet --regex '^[0-9]+$' -- $pid
                    set --append valid_pids $pid
                end
            end

            if test (count $valid_pids) -eq 0
                echo "🚫 No valid process ids selected." >&2
            else if set -q TMUX; and type -q tmux
                set -l kill_command "set -l pids $valid_pids; echo 'Killing process(es):' \$pids; if type -q murder; for pid in \$pids; murder -y \$pid; end; else; kill -9 \$pids; end; sleep 1s; tmux kill-pane -t \$TMUX_PANE 2>/dev/null"
                set -l tmux_command "fish -lc "(string escape -- $kill_command)
                command tmux split-window -d -h -l 40 -- $tmux_command
            else
                echo "Killing process(es): "(string join ' ' $valid_pids)
                if type -q murder
                    for pid in $valid_pids
                        murder -y $pid &
                    end
                else
                    kill -9 $valid_pids
                end
            end
        end
    end

    commandline --function repaint
end
