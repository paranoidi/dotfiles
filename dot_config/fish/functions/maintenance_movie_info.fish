function maintenance_movie_info
    argparse h/help f/force i/install -- $argv
    or return

    if set -q _flag_help
        echo "usage: maintenance_movie_info [-f|--force] [-i|--install]"
        return 0
    end

    if set -q _flag_install
        if not type -q go
            echo "🚫 maintenance_movie_info: go is not available on PATH" >&2
            return 1
        end

        tmux-progress "📥 movie-info update"

        # GOPROXY=direct bypasses the module proxy to avoid stale cached module zips
        set -l install_flags -v
        if set -q _flag_force
            set -a install_flags -a
        end

        if not env GOPROXY=direct go install $install_flags github.com/paranoidi/movie-info@main
            echo "🚫 maintenance_movie_info: go install failed" >&2
            tmux-progress clear
            return 1
        end

        set -l mi_bin (path normalize (go env GOPATH)/bin/movie-info)
        set -l mi_version
        set -l go_toolchain
        if test -f $mi_bin
            for line in (go version -m $mi_bin 2>/dev/null)
                if string match -qr ': go' -- $line
                    set go_toolchain (string replace -r '^[^:]+: ' '' -- $line)
                else if string match -qr '^\tmod\t' -- $line
                    set -l mod_fields (string split \t -- $line)
                    set mi_version $mod_fields[4]
                end
            end
        end
        if test -z "$mi_version"
            set mi_version (env GOPROXY=direct go list -m -f '{{.Version}}' github.com/paranoidi/movie-info@main 2>/dev/null)
        end

        set -l message 'movie-info updated'
        if test -n "$mi_version"; and test -n "$go_toolchain"
            set message "$message ($mi_version, $go_toolchain)"
        else if test -n "$mi_version"
            set message "$message ($mi_version)"
        else if test -n "$go_toolchain"
            set message "$message ($go_toolchain)"
        end

        toast -i '🏆' $message
        tmux-progress clear
        return 0
    end

    if not type -q tsp
        echo "🚫 Skipping maintenance_movie_info: tsp is not available on PATH" >&2
        return 1
    end

    if not type -q go
        echo "🚫 Skipping maintenance_movie_info: go is not available on PATH" >&2
        return 1
    end

    set -l script maintenance_movie_info --install
    if set -q _flag_force
        set -a script --force
    end

    tsp -L maintenance_movie_info fish -c (string join ' ' -- $script) >/dev/null
end
