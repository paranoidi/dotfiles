function fish_user_key_bindings
    # fzf.fish installs canonical key name bindings (ctrl-r, ctrl-v, ctrl-alt-*)
    # which cause a 'c' input delay due to fish key sequence disambiguation.
    # Disable them all here; we manage all bindings manually below.
    if functions -q fzf_configure_bindings
        fzf_configure_bindings --directory= --git_log= --git_status= --history= --processes= --variables=

        bind \cT fzf_insert_file
        bind \ec fzf_cd

        bind \cr _fzf_search_history
        bind -M insert \cr _fzf_search_history

        bind \cP _fzf_search_processes
        bind -M insert \cP _fzf_search_processes

        bind \e\cP fzf_kill_process
        bind -M insert \e\cP fzf_kill_process

        bind \e\cV "$_fzf_search_vars_command"
        bind -M insert \e\cV "$_fzf_search_vars_command"
    end

    # Remove terminal key-sequence noise.
    bind \e\[5\;3\~ ''
    bind \e\[6\;3\~ ''
    bind \e\[1\;5A ''
    bind \e\[1\;5B ''
    bind \e\[5\;5\~ ''
    bind \e\[6\;5\~ ''

    # Global fzf options
    # Use Ctrl+P to toggle preview panels instead of Ctrl+/ (impossible to type on Finnish keyboard)
    set -gx FZF_DEFAULT_OPTS '--cycle --layout=reverse --border --height=90% --preview-window=wrap --marker="*" --bind="ctrl-p:toggle-preview"'

    # Override fzf-git's internal wrapper so it uses Ctrl+P for preview toggle too
    set -gx __fzf_git_fzf '
    _fzf_git_fzf() {
    fzf --height 50% --tmux 90%,70% \
        --layout reverse --multi --min-height 20+ --border \
        --no-separator --header-border horizontal \
        --border-label-pos 2 \
        --color '\''label:blue'\'' \
        --preview-window '\''right,50%'\'' --preview-border line \
        --bind '\''ctrl-p:change-preview-window(down,50%|hidden|)'\'' "$@"
    }
    '
end
