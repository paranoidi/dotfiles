function __is_terminal_focused --description 'Returns 0 if the focused window is a terminal emulator'
    set -l terms alacritty kitty foot gnome-terminal xterm urxvt konsole wezterm tilix terminator rxvt st xfce4-terminal ghostty

    # Sway / i3 (Wayland)
    if type -q swaymsg
        set -l focused (swaymsg -t get_tree 2>/dev/null \
            | jq -r '.. | objects | select(.focused == true) | (.app_id // .window_properties.class // "")' 2>/dev/null \
            | head -1 | string lower)
        for term in $terms
            string match -q "*$term*" -- $focused; and return 0
        end
        return 1
    end

    # Hyprland (Wayland)
    if type -q hyprctl
        set -l focused (hyprctl activewindow -j 2>/dev/null | jq -r '(.class // "")' 2>/dev/null | string lower)
        for term in $terms
            string match -q "*$term*" -- $focused; and return 0
        end
        return 1
    end

    # X11 via xprop
    if type -q xprop; and set -q DISPLAY
        set -l win_id (xprop -root 32x '\t$0' _NET_ACTIVE_WINDOW 2>/dev/null | cut -f2)
        if test -n "$win_id"
            # Strip 'WM_CLASS(STRING) = ' prefix so "st" doesn't match "string"
            set -l focused (xprop -id $win_id WM_CLASS 2>/dev/null \
                | string replace -r '^[^=]+=\s*' '' | string lower)
            for term in $terms
                string match -q "*$term*" -- $focused; and return 0
            end
        end
        return 1
    end

    return 1
end
