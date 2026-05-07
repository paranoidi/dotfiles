function fisher_sync
    if set -q __fisher_sync_running
        return
    end

    set -l force 0
    for arg in $argv
        switch $arg
            case -f --force
                set force 1
        end
    end

    set -l plugin_file $XDG_CONFIG_HOME/fish/fish_plugins
    if not test -f $plugin_file
        return
    end

    if not functions -q fisher
        set -l fisher_file $XDG_CONFIG_HOME/fish/functions/fisher.fish
        if test -f $fisher_file
            source $fisher_file
        else
            return
        end
    end

    set -gx __fisher_sync_running 1

    for plugin in (string match -rv '^\s*(#|$)' < $plugin_file)
        if not fisher list | grep -qx -- $plugin
            if test $force -eq 1
                set -l fisher_output (fisher install $plugin 2>&1)
                set -l fisher_status $status
                if test $fisher_status -ne 0
                    # Parse conflicting files from fisher error output and remove them
                    set -l conflicts (string match -r '^\s+(/\S+\.fish)$' -- $fisher_output | string trim)
                    if test (count $conflicts) -gt 0
                        echo "🔧 Removing "(count $conflicts)" conflicting file(s) for $plugin"
                        for f in $conflicts
                            rm -f -- $f
                            and echo "  removed $f"
                        end
                        _spinner --fallback-prefix "🔌" "Installing fisher plugin $plugin ..." fisher install $plugin
                    else
                        echo $fisher_output >&2
                    end
                end
            else
                _spinner --fallback-prefix "🔌" "Installing fisher plugin $plugin ..." fisher install $plugin
            end
        end
    end

    set -e __fisher_sync_running
end
