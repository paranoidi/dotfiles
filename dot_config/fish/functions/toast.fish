function toast
    argparse 'i/icon=' -- $argv
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
            if not __claude_active_window_is_terminal
                command notify-send "$text" 2>/dev/null &
            end
        end
    end
end
