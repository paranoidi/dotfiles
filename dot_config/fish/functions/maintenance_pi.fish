function maintenance_pi
    argparse f/force -- $argv
    or return

    if not type -q tsp
        echo "🚫 Skipping maintenance_pi: tsp is not available on PATH" >&2
        return 1
    end

    if type -q nvm
        set -l cache_dir ~/.cache/fish
        set -l timestamp_file $cache_dir/last_pi_run
        set -l current_time (date +%s)
        set -l should_run false

        if not test -d $cache_dir
            mkdir -p $cache_dir
        end

        if set -q _flag_force
            set should_run true
        else if test -f $timestamp_file
            set -l last_run (string trim -- (command cat $timestamp_file))

            if test (count $last_run) -eq 1; and string match -qr '^[0-9]+$' -- $last_run
                if test (math "$current_time - $last_run") -ge 604800
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

        # Keep JS packages seven days old since supply chains move fast.
        tsp fish -c "nvm use latest && tmux-progress '📥 pi update' npm install --min-release-age=7 -g @mariozechner/pi-coding-agent" > /dev/null
        echo $current_time > $timestamp_file
    else
        echo "🚫 nvm is not installed on this machine"
    end
end
