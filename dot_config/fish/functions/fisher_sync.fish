function fisher_sync
    if set -q __fisher_sync_running
        echo "🔵 fisher_sync is already running, skipping"
        return
    end

    set -l plugin_file $XDG_CONFIG_HOME/fish/fish_plugins
    if not test -f $plugin_file
        echo "📋 No fish_plugins file found at $plugin_file, nothing to sync"
        return
    end

    if not functions -q fisher
        set -l fisher_file $XDG_CONFIG_HOME/fish/functions/fisher.fish
        if test -f $fisher_file
            source $fisher_file
        else
            echo "❌ fisher not found — expected $fisher_file"
            return
        end
    end

    set -gx __fisher_sync_running 1

    set -l plugins (string match -rv '^\s*(#|$)' < $plugin_file)
    if test (count $plugins) -eq 0
        echo "📋 fish_plugins is empty, nothing to sync"
        set -e __fisher_sync_running
        return
    end

    set -l installed_count 0
    set -l skipped_count 0

    for plugin in $plugins
        if fisher list | grep -qx -- $plugin
            set skipped_count (math $skipped_count + 1)
        else
            set -l max_retries 3
            set -l attempt 0
            set -l installed 0
            while test $attempt -lt $max_retries
                set attempt (math $attempt + 1)
                set -l fisher_output (fisher install $plugin 2>&1)
                set -l fisher_status $status
                if test $fisher_status -eq 0
                    set installed 1
                    break
                end
                # Parse conflicting files from fisher error output and move them to trash
                set -l conflicts (string match -r '^\s+(/\S+\.fish)$' -- $fisher_output | string trim)
                if test (count $conflicts) -gt 0
                    set -l trash_dir $XDG_CONFIG_HOME/fish/functions/trash
                    mkdir -p $trash_dir
                    echo "🧹 Moving "(count $conflicts)" conflicting file(s) to trash for $plugin (attempt $attempt/$max_retries)"
                    for f in $conflicts
                        if test -f $f
                            mv -- $f $trash_dir/
                            and echo "  💀 $f"
                        end
                    end
                else
                    echo "❌ fisher install $plugin failed:" >&2
                    echo $fisher_output >&2
                    break
                end
            end
            if test $installed -eq 1
                set installed_count (math $installed_count + 1)
                echo "✅ $plugin installed"
            else
                echo "💥 Failed to install $plugin after $attempt attempt(s)" >&2
            end
        end
    end

    if test $installed_count -gt 0
        echo "🎉 Installed $installed_count plugin(s), $skipped_count already up to date"
    else
        echo "✅ All $skipped_count plugin(s) already installed"
    end

    set -e __fisher_sync_running
end
