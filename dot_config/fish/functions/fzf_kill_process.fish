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
            echo "Killing process(es): "(string join ' ' $pids)
            if type -q murder
                for pid in $pids
                    murder -y $pid
                end
            else
                kill -9 $pids
            end
        end
    end

    commandline --function repaint
end
