function wait-pids \
    --description "Wait for PIDs to exit; usable with && chaining"

    argparse 'timeout=' 'interval=' 'any' -- $argv
    or return 1

    set -l pids $argv

    if test (count $pids) -eq 0
        if not command -q fzf
            echo "wait-pids: no PIDs given and fzf not found" >&2
            return 1
        end
        set pids (ps u --no-headers --sort=-start \
            | awk '{cmd=""; for(i=11;i<=NF;i++) cmd=cmd (i>11?" ":"") $i; if ($11 !~ /(\/|^)(ps|awk|fzf)$/) printf "%7s %5s %5s %8s %8s  %s\n", $2, $3, $4, $9, $10, cmd}' \
            | fzf --multi --prompt="Select processes> " \
            | awk '{print $1}')
        if test (count $pids) -eq 0
            return 1
        end
    end

    set -l timeout 0
    set -q _flag_timeout; and set timeout $_flag_timeout

    set -l interval 0.2
    set -q _flag_interval; and set interval $_flag_interval

    set -l mode all
    set -q _flag_any; and set mode any

    set -l start (date +%s)

    while true
        set -l alive

        for pid in $pids
            kill -0 $pid 2>/dev/null
            and set alive $alive $pid
        end

        # success conditions
        if test "$mode" = "any"
            if test (count $alive) -lt (count $pids)
                return 0
            end
        else
            if test (count $alive) -eq 0
                return 0
            end
        end

        # timeout
        if test $timeout -gt 0
            set -l now (date +%s)
            if test (math "$now - $start") -ge $timeout
                return 1
            end
        end

        sleep $interval
    end
end
