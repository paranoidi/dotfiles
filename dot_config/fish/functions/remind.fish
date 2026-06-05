function remind --description "Set a reminder: remind <duration> <msg> (e.g. remind 1h30m 'Take a break')"
    if test (count $argv) -lt 2
        echo "Usage: remind <duration> <msg>"
        echo "Duration format: 1h30m, 1h, 30m, 30min, 1h30min, or 14:30"
        return 1
    end

    set duration $argv[1]
    set msg $argv[2..-1]

    # Parse duration: optional hours and optional minutes
    set hours 0
    set minutes 0
    set total_seconds 0
    set label ""

    if string match -qr '^\d{1,2}:\d{2}$' -- $duration
        # Explicit time format hh:mm
        set parts (string split ':' $duration)
        set target_h $parts[1]
        set target_m $parts[2]
        if test $target_h -gt 23 -o $target_m -gt 59
            echo "Invalid time: $duration (must be 00:00–23:59)"
            return 1
        end
        set now_seconds (date +%s)
        set target_seconds (date -d "today $target_h:$target_m" +%s)
        if test $target_seconds -le $now_seconds
            set target_seconds (date -d "tomorrow $target_h:$target_m" +%s)
            set label "at $target_h:$target_m tomorrow"
        else
            set label "at $target_h:$target_m today"
        end
        set total_seconds (math "$target_seconds - $now_seconds")
    else if string match -qr '^(?:\d+h)?(?:\d+m(?:in)?)?$' -- $duration
        # Relative duration format: 1h30m, 2h, 45m, 20min, 1h20min
        set hparts (string match -r '(\d+)h' -- $duration)
        set mparts (string match -r '(\d+)m(?:in)?' -- $duration)
        if test (count $hparts) -ge 2; set hours $hparts[2]; end
        if test (count $mparts) -ge 2; set minutes $mparts[2]; end

        if test $hours -eq 0 -a $minutes -eq 0
            echo "Duration must be greater than zero"
            return 1
        end

        set total_seconds (math "$hours * 3600 + $minutes * 60")

        set label ""
        if test $hours -gt 0
            set label "$hours h "
        end
        if test $minutes -gt 0
            set label "$label$minutes min"
        end
        set label "in "(string trim $label)
    else
        echo "Invalid duration format: $duration"
        echo "Expected format: 1h30m, 1h, 30m, 30min, 1h30min, or 14:30"
        return 1
    end

    echo "Reminder set: '$msg' $label"

    # Pick notification method: graphical → notify-send, tmux fallback → display-message
    if test -n "$DISPLAY" -o -n "$WAYLAND_DISPLAY"
        set notify_cmd "notify-send -u normal '⏰ Reminder' '$msg'"
    else if set -q TMUX; and command -v tmux >/dev/null 2>&1
        # -d 0 keeps the message until a key is pressed; tmux socket is inherited via $TMUX
        set notify_cmd "tmux display-message -d 0 '⏰ Reminder: $msg'"
    else
        set notify_cmd ""
    end

    if test -z "$notify_cmd"
        echo "Warning: no notification method available (no display, no tmux)" >&2
        return 0
    end

    # Run in a new session so it survives terminal close
    setsid fish -c "sleep $total_seconds; $notify_cmd" &>/dev/null &
    disown
end
