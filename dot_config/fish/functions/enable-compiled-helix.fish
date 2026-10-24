function enable-compiled-helix --description 'Build helix from source on this host (--off: back to prebuilt mise helix)'
    set --local flag ~/.config/chezmoi/features/compiled-helix
    set --local script (chezmoi source-path)/bin/run_onchange_install-packages.sh

    switch "$argv[1]"
        case --off
            rm -f $flag
        case ''
            mkdir -p (dirname $flag)
            touch $flag
        case '*'
            echo 'Usage: enable-compiled-helix [--off]'
            return 1
    end

    # Re-render mise.toml (helix entry is gated on the flag), then (re)install.
    chezmoi apply ~/.config/mise/mise.toml; or return
    if test "$argv[1]" = --off
        mise install -y helix
    else
        bash $script --force helix
    end
end
