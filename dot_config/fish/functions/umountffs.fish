function umountffs --description 'Umount with process resolution via fzf'
    set -l target "$argv[1]"

    if test -z "$target"
        echo "Usage: umountffs <mount-point>" >&2
        return 1
    end

    # Step 1: try normal umount first — fast path
    if command umount "$target" 2>/dev/null
        return 0
    end

    echo "🔍 Scanning for processes using $target ..." >&2

    if not type -q fuser
        echo "🚫 fuser not found. Try: sudo lsof +D $target" >&2
        return 1
    end

    # Step 2: get PIDs via fuser -m (purpose-built for "who's using this mount")
    set -l fuser_raw (command fuser -m "$target" 2>/dev/null)
    if test -z "$fuser_raw"
        echo "💬 No processes found via fuser. The mount may be busy for other reasons." >&2
        echo "🔧 Try: sudo umount $target" >&2
        return 1
    end

    # fuser output: "/mount/point: 1234 5678" — extract numeric PIDs after colon
    set -l fuser_parts (string split ':' -- $fuser_raw)
    set -l pids (string split ' ' -- $fuser_parts[2..-1] 2>/dev/null | string match --regex '^[0-9]+$')

    if test (count $pids) -eq 0
        echo "❌ Could not parse PIDs from fuser output." >&2
        return 1
    end

    # Step 3: build process table and present via fzf
    set -l proc_info (command ps -p $pids -o pid=,user=,args= 2>/dev/null | string trim)
    if test -z "$proc_info"
        echo "❌ Could not retrieve process information." >&2
        return 1
    end

    set -l selected (
        printf '%s\n' $proc_info | \
        _fzf_wrapper --multi \
            --prompt="Select processes to murder (blocking $target)> " \
            --preview="ps -p {1} -o pid,ppid=PARENT,user,\\%cpu,rss=RSS_IN_KB,start=START_TIME,command 2>/dev/null" \
            --preview-window="bottom:4:wrap"
    )

    if test $status -ne 0; or test (count $selected) -eq 0
        echo "🚫 No processes selected. Aborting." >&2
        return 1
    end

    # Step 4: extract PIDs from fzf selections and murder them
    set -l kill_pids
    for line in $selected
        set -l pid (string split --field=1 -- ' ' (string trim -- $line))
        if string match --quiet --regex '^[0-9]+$' -- $pid
            set --append kill_pids $pid
        end
    end

    if test (count $kill_pids) -eq 0
        echo "🚫 No valid PIDs selected." >&2
        return 1
    end

    echo "💀 Killing "(count $kill_pids)" process(es) ..." >&2
    for pid in $kill_pids
        murder -y $pid
    end

    # Step 5: retry umount
    echo "🔧 Retrying umount $target ..." >&2
    command umount "$target"
    set -l umount_status $status

    if test $umount_status -eq 0
        echo "✅ $target unmounted successfully." >&2
    else
        echo "🚫 Umount still failed. Manual intervention may be needed." >&2
        echo "🔧 Try: sudo lsof +D $target" >&2
    end

    return $umount_status
end
