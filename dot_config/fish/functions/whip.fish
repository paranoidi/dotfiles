function whip --description 'Schedule text to a tmux window at hh:mm or after a duration'
    set -l usage "Usage: whip hh:mm|duration [text]
       whip hh:mm|duration -     send Enter only
       whip ls
       whip cancel [pid]

duration: 30min, 1h, 1h30min, 1h30m"

    if test (count $argv) -eq 0
        echo $usage
        return 1
    end

    switch $argv[1]
        case ls
            __whip_list
            return
        case cancel c
            __whip_cancel $argv[2..-1]
            return
        case -h --help help
            echo $usage
            return 0
    end

    if test (count $argv) -gt 2
        echo $usage
        return 1
    end

    set -l when $argv[1]
    set text resume
    if test (count $argv) -eq 2
        if test "$argv[2]" = -
            set text ""
        else
            set text $argv[2]
        end
    end

    set -l now_epoch (date +%s)
    set target_epoch (__whip_parse_time $when $now_epoch)
    if test -z "$target_epoch"
        echo "🚫 whip: invalid time '$when' — use hh:mm (24h) or duration (30min, 1h, 1h30min)"
        return 1
    end

    set -l at_display (date -d "@$target_epoch" +%H:%M 2>/dev/null)
    test -z "$at_display"; and set at_display $when

    # Seconds until target
    set diff (math "$target_epoch - $now_epoch")
    if test "$diff" -le 0
        set diff (math "$diff + 86400")
        set target_epoch (math "$target_epoch + 86400")
        set at_display (date -d "@$target_epoch" +%H:%M 2>/dev/null)
    end

    # fzf pick tmux window with live pane preview
    # Use #{window_id} (@N) — stable across reorganizations, unlike #I
    set preview "fish -c 'set -l p (string split -m 2 : -- \$argv[1]); command tmux capture-pane -t \"\$p[2]\" -p -e 2>/dev/null | head -30' -- {}"

    set selection (
        command tmux list-windows -a -F '#S:#{window_id}: #W' 2>/dev/null |
        fzf --height=60% --reverse --border \
            --header="whip $when — pick target window" \
            --preview="$preview" --preview-window=right:50%
    )

    test -z "$selection" && return 0

    # #{window_id} (@N) is unique within a tmux server — no session prefix needed
    set target_id (string split -m 2 : -- "$selection")[2]

    set -l jobfile (__whip_jobfile)
    set -l jobfile_esc (string escape -- $jobfile)
    set -l esc_text (string escape -- $text)

    # Background fish is process-group leader (job control); cancel uses kill -- -$pid
    # Do not use setsid: when already a PG leader it forks and $last_pid dies immediately
    #
    # Agent TUIs (Claude Code / cursor-agent): text+Enter in one send-keys write is often
    # treated as a soft newline (Shift+Enter). Send literal text, then Enter alone, then a
    # second Enter after a beat (queue/"send now" confirm).
    set -l send_body "
        sleep $diff
        and begin
    "
    if test -n "$text"
        set send_body "$send_body
            command tmux send-keys -t $target_id -l -- $esc_text
            sleep 0.2
            command tmux send-keys -t $target_id Enter
            sleep 0.5
            command tmux send-keys -t $target_id Enter
        "
    else
        set send_body "$send_body
            command tmux send-keys -t $target_id Enter
        "
    end
    set send_body "$send_body
        end
    "

    fish -c "$send_body
        set -l f $jobfile_esc
        if test -f \$f
            grep -v \"^\$fish_pid	\" \$f > \$f.tmp 2>/dev/null
            and mv \$f.tmp \$f
        end
    " >/dev/null 2>&1 &
    set -l pid $last_pid
    disown

    set -l text_label $text
    test -z "$text_label"; and set text_label '(enter)'

    printf '%s\t%s\t%s\t%s\t%s\n' $pid $at_display $target_id $target_epoch $text >>$jobfile
    set -l when_note ""
    if test "$when" != "$at_display"
        set when_note " ($when)"
    end
    echo "🏆 $text_label → $target_id @ $at_display$when_note (in "(math -s0 "$diff / 60")"m, pid $pid)"
end

function __whip_parse_time -a when -a now_epoch
    # Absolute hh:mm (24h); roll to tomorrow if already past
    if string match -qr '^\d{1,2}:\d{2}$' -- $when
        set -l target_epoch (date -d $when +%s 2>/dev/null)
        if test -n "$target_epoch"
            if test (math "$target_epoch - $now_epoch") -le 0
                set target_epoch (math "$target_epoch + 86400")
            end
            echo $target_epoch
            return 0
        end
        return 1
    end

    set -l when_lc (string lower -- $when)
    set -l seconds 0
    set -l matched false

    set -l parts (string match -r -i '^(\d+)h(\d+)(?:min|m)?$' -- $when_lc)
    if test (count $parts) -ge 3
        set seconds (math "$parts[2] * 3600 + $parts[3] * 60")
        set matched true
    else
        set parts (string match -r -i '^(\d+)h$' -- $when_lc)
        if test (count $parts) -ge 2
            set seconds (math "$parts[2] * 3600")
            set matched true
        else
            set parts (string match -r -i '^(\d+)(?:min|m)$' -- $when_lc)
            if test (count $parts) -ge 2
                set seconds (math "$parts[2] * 60")
                set matched true
            end
        end
    end

    if test "$matched" = false; or test "$seconds" -le 0
        return 1
    end

    echo (math "$now_epoch + $seconds")
end

function __whip_jobfile
    if set -q XDG_RUNTIME_DIR; and test -n "$XDG_RUNTIME_DIR"
        echo $XDG_RUNTIME_DIR/whip.jobs
    else
        echo /tmp/whip-$UID.jobs
    end
end

function __whip_prune
    set -l jobfile (__whip_jobfile)
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

function __whip_list
    __whip_prune
    set -l jobfile (__whip_jobfile)
    if not test -f $jobfile
        echo "No scheduled whips."
        return 0
    end

    set -l now (date +%s)
    printf '%-8s %-7s %-10s %s\n' PID AT WINDOW TEXT
    for line in (cat $jobfile)
        set -l fields (string split -m 4 \t -- $line)
        set -l pid $fields[1]
        set -l at $fields[2]
        set -l window $fields[3]
        set -l epoch $fields[4]
        set -l text $fields[5]
        set -l mins (math -s0 "max(0, ($epoch - $now) / 60)")
        printf '%-8s %-7s %-10s %s (in %sm)\n' $pid $at $window $text $mins
    end
end

function __whip_cancel
    __whip_prune
    set -l jobfile (__whip_jobfile)
    if not test -f $jobfile
        echo "No scheduled whips."
        return 0
    end

    set -l pids $argv
    if test (count $pids) -eq 0
        if not type -q fzf
            echo "Usage: whip cancel <pid>"
            return 1
        end
        set -l now (date +%s)
        set -l selection (
            for line in (cat $jobfile)
                set -l fields (string split -m 4 \t -- $line)
                set -l mins (math -s0 "max(0, ($fields[4] - $now) / 60)")
                printf '%s\t%s → %s @ %s (in %sm)\n' $fields[1] $fields[5] $fields[3] $fields[2] $mins
            end | fzf --height=60% --reverse --border --multi \
                --header="whip cancel — pick job(s)" \
                --with-nth=2..
        )
        test -z "$selection"; and return 0
        set pids
        for s in $selection
            set pids $pids (string split -f 1 \t -- $s)[1]
        end
    end

    set -l cancelled 0
    for pid in $pids
        if not kill -0 $pid 2>/dev/null
            echo "🚫 whip: no job with pid $pid"
            continue
        end
        # Kill process group so sleep child dies too
        kill -- -$pid 2>/dev/null
        or kill $pid 2>/dev/null
        or begin
            echo "🚫 whip: failed to kill pid $pid"
            continue
        end
        set cancelled (math "$cancelled + 1")
    end

    __whip_prune
    if test $cancelled -gt 0
        set -l plural s
        test $cancelled -eq 1; and set plural ""
        echo "🏆 Cancelled $cancelled whip$plural"
    end
end
