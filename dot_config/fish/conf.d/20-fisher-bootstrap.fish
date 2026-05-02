# Automatically install fisher and plugins only for interactive shells.
if status is-interactive; and not set -q __fisher_sync_running
    set -l fisher_file $XDG_CONFIG_HOME/fish/functions/fisher.fish

    if not test -f $fisher_file
        _spinner --fallback-prefix "🌐" "Installing fisher ..." curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish --create-dirs -o $fisher_file
    end

    if not functions -q fisher
        source $fisher_file
    end

    fisher_sync
end
