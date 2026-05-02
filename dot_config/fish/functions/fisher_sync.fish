function fisher_sync
    if set -q __fisher_sync_running
        return
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
            _spinner --fallback-prefix "🔌" "Installing fisher plugin $plugin ..." fisher install $plugin
        end
    end

    set -e __fisher_sync_running
end
