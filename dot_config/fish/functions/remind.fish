function remind --description "Set a reminder: remind <duration> <msg> (e.g. remind 1h30m 'Take a break')"
    if test (count $argv) -ge 1 -a "$argv[1]" = ls
        __remind_list
        return
    end

    if test (count $argv) -lt 2
        echo "Usage: remind <duration> <msg>"
        echo "       remind ls"
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
            echo "🚫 Invalid time: $duration (must be 00:00–23:59)"
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
            echo "🚫 Duration must be greater than zero"
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
        echo "🚫 Invalid duration format: $duration"
        echo "Expected format: 1h30m, 1h, 30m, 30min, 1h30min, or 14:30"
        return 1
    end

    set -l target_epoch (math (date +%s) + $total_seconds)
    set -l jobfile (__remind_jobfile)
    set -l jobfile_esc (string escape -- $jobfile)
    set escaped_msg (string escape -- (string join ' ' -- $msg))

    # -f forces the desktop notification even if a terminal is focused —
    # without it toast skips notify-send whenever you're sitting at any
    # terminal, which is exactly when a reminder needs to show up.
    setsid fish -c "
        sleep $total_seconds
        toast -f -i ⏰ $escaped_msg
        set -l f $jobfile_esc
        if test -f \$f
            grep -v \"^\$fish_pid	\" \$f > \$f.tmp 2>/dev/null
            and mv \$f.tmp \$f
        end
    " &>/dev/null &
    set -l pid $last_pid
    disown

    printf '%s\t%s\t%s\n' $pid $target_epoch (string join ' ' -- $msg) >>$jobfile

    echo "🏆 Reminder set: '$msg' $label (pid $pid)"
end

function __remind_jobfile
    if set -q XDG_RUNTIME_DIR; and test -n "$XDG_RUNTIME_DIR"
        echo $XDG_RUNTIME_DIR/remind.jobs
    else
        echo /tmp/remind-$UID.jobs
    end
end

function __remind_prune
    set -l jobfile (__remind_jobfile)
    test -f $jobfile; or return 0

    set -l kept
    for line in (cat $jobfile)
        set -l pid (string split -f 1 \t -- $line)[1]
        if kill -0 $pid 2>/dev/null
            set kept $kept $line
        end
    end

    if test (count $kept) -eq 0
        rm -f $jobfile
    else
        printf '%s\n' $kept >$jobfile
    end
end

function __remind_list
    __remind_prune
    set -l jobfile (__remind_jobfile)
    if not test -f $jobfile
        echo "No scheduled reminders."
        return 0
    end

    set -l now (date +%s)
    printf '%-8s %-7s %s\n' PID AT TEXT
    for line in (cat $jobfile)
        set -l fields (string split -m 2 \t -- $line)
        set -l pid $fields[1]
        set -l epoch $fields[2]
        set -l msg $fields[3]
        set -l at (date -d "@$epoch" +%H:%M 2>/dev/null)
        set -l mins (math -s0 "max(0, ($epoch - $now) / 60)")
        printf '%-8s %-7s %s (in %sm)\n' $pid $at $msg $mins
    end
end
