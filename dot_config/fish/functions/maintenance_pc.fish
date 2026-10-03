function maintenance_pc
    argparse h/help f/force i/install -- $argv
    or return

    if set -q _flag_help
        echo "usage: maintenance_pc [-f|--force] [-i|--install]"
        return 0
    end

    if set -q _flag_install
        if not type -q go
            echo "🚫 maintenance_pc: go is not available on PATH" >&2
            return 1
        end

        tmux-progress "📥 pc update"

        # GOPROXY=direct bypasses the module proxy to avoid stale cached module zips
        set -l install_flags -v
        if set -q _flag_force
            set -a install_flags -a
        end

        # mise sets GOBIN to its per-version go dir; pin pc to ~/go/bin instead so
        # it survives go upgrades and there is exactly one copy
        set -l pc_dir (path normalize (go env GOPATH)/bin)
        set -l pc_bin $pc_dir/pc

        if not env GOPROXY=direct GOBIN=$pc_dir go install $install_flags github.com/paranoidi/paras-commander/cmd/pc@main
            echo "🚫 maintenance_pc: go install failed" >&2
            tmux-progress clear
            return 1
        end

        # Purge copies left in mise go installs by earlier runs
        for stray in ~/.local/share/mise/installs/go/*/bin/pc
            rm -f -- $stray
            and echo "🧹 maintenance_pc: removed $stray"
        end

        set -l resolved (command -v pc)
        if test "$resolved" != "$pc_bin"
            echo "🚫 maintenance_pc: 'pc' resolves to $resolved, not $pc_bin — fix PATH order" >&2
            tmux-progress clear
            return 1
        end

        set -l pc_version
        set -l go_toolchain
        if test -f $pc_bin
            for line in (go version -m $pc_bin 2>/dev/null)
                if string match -qr ': go' -- $line
                    set go_toolchain (string replace -r '^[^:]+: ' '' -- $line)
                else if string match -qr '^\tmod\t' -- $line
                    set -l mod_fields (string split \t -- $line)
                    set pc_version $mod_fields[4]
                end
            end
        end
        if test -z "$pc_version"
            set pc_version (env GOPROXY=direct go list -m -f '{{.Version}}' github.com/paranoidi/paras-commander@main 2>/dev/null)
        end

        set -l message 'pc updated'
        if test -n "$pc_version"; and test -n "$go_toolchain"
            set message "$message ($pc_version, $go_toolchain)"
        else if test -n "$pc_version"
            set message "$message ($pc_version)"
        else if test -n "$go_toolchain"
            set message "$message ($go_toolchain)"
        end

        toast -i '🏆' $message
        tmux-progress clear
        return 0
    end

    if not type -q tsp
        echo "🚫 Skipping maintenance_pc: tsp is not available on PATH" >&2
        return 1
    end

    if not type -q go
        echo "🚫 Skipping maintenance_pc: go is not available on PATH" >&2
        return 1
    end

    set -l script maintenance_pc --install
    if set -q _flag_force
        set -a script --force
    end

    tsp -L maintenance_pc fish -c (string join ' ' -- $script) >/dev/null
end
