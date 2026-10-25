function _clipboard_copy --description '📋 Copy stdin to the best available clipboard'
    if set -q WAYLAND_DISPLAY; and type -q wl-copy
        wl-copy
    else if set -q DISPLAY; and type -q xclip
        xclip -selection clipboard
    else if set -q TMUX; and type -q tmux
        # -w also forwards to the outer terminal clipboard via OSC 52
        tmux load-buffer -w -
    else if test -w /dev/tty
        # OSC 52: ask the terminal emulator to set its clipboard
        printf '\e]52;c;%s\a' (base64 -w0) >/dev/tty
    else
        echo "🚫 no clipboard available (wl-copy, xclip, tmux or a tty)" >&2
        return 1
    end
end
