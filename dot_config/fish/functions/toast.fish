function toast
    argparse 'i/icon=' 's/stick' -- $argv
    or return

    set -l text (string join ' ' -- $argv)
    if test -z "$text"
        echo "usage: toast [-i ICON] MESSAGE" >&2
        return 1
    end

    set -l message $text
    if set -q _flag_icon
        set message " $_flag_icon $message"
    end

    if command -v tmux >/dev/null 2>&1
        command tmux display-message " $message" 2>/dev/null &
    end

    if command -v notify-send >/dev/null 2>&1
        if test -n "$DISPLAY" -o -n "$WAYLAND_DISPLAY"
            if not __is_terminal_focused
                set -l timeout 3500
                if set -q _flag_stick
                    set timeout 0
                end
                command notify-send -t $timeout "$text" 2>/dev/null &
            end
        end
    end
end
