function tmux-progress -d "Show <text> in tmux status-right; auto [i/N]-counts concurrent callers. Optional trailing <cmd> auto-clears on exit."
    if test (count $argv) -eq 0
        echo "usage: tmux-progress <text>          show text in tmux status-right"
        echo "       tmux-progress <text> <cmd...>  show text while cmd runs, auto-clear on exit"
        echo "       tmux-progress clear            clear your own status text"
        return 1
    end

    set -l dir /tmp/.tmux-progress
    mkdir -p $dir

    if test "$argv[1]" = clear
        rm -f $dir/$fish_pid
        _tmux-progress-render
        return
    end

    set -l text $argv[1]
    set -l cmd $argv[2..-1]
    echo $text >$dir/$fish_pid
    _tmux-progress-render

    if test (count $cmd) -gt 0
        $cmd
        set -l cmd_status $status
        rm -f $dir/$fish_pid
        _tmux-progress-render
        return $cmd_status
    end
end
