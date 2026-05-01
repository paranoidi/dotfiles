function dailymaintenance
    set -l cache_dir ~/.cache/fish
    set -l timestamp_file $cache_dir/last_daily_run

    if not test -d $cache_dir
        mkdir -p $cache_dir
    end

    set -l current_time (date +%s)
    set -l should_run false

    if test -f $timestamp_file
        set -l last_run (string trim -- (command cat $timestamp_file))

        if test (count $last_run) -eq 1; and string match -qr '^[0-9]+$' -- $last_run
            set -l time_diff (math "$current_time - $last_run")

            if test "$time_diff" -ge 86400
                set should_run true
            end
        else
            set should_run true
        end
    else
        set should_run true
    end

    if test "$should_run" != true
        return
    end

    echo "🛠️ Running daily maintenance tasks at "(date)

    set -l maintenance_functions
    for function_dir in $fish_function_path
        for function_file in (path filter -f -- $function_dir/maintenance_*.fish)
            set -a maintenance_functions (path change-extension '' (path basename $function_file))
        end
    end

    for maintenance_function in (printf '%s\n' $maintenance_functions | sort -u)
        $maintenance_function
    end

    echo $current_time > $timestamp_file
end
