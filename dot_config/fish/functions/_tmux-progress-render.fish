function _tmux-progress-render
    set -l dir /tmp/.tmux-progress
    for marker in $dir/*
        kill -0 (path basename $marker) 2>/dev/null; or rm -f $marker
    end
    set -l files (command ls -tr $dir 2>/dev/null)
    if test (count $files) -eq 0
        tmux set -g @progress ""
    else
        set -l total (count $files)
        set -l newest $files[-1]
        set -l text (cat $dir/$newest)
        set -l index (contains -i -- $newest $files)
        if test $total -gt 1
            tmux set -g @progress "[$index/$total] $text"
        else
            tmux set -g @progress "$text"
        end
    end
    tmux refresh-client -S
end
