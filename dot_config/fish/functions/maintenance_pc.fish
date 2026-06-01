function maintenance_pc
    argparse f/force i/install -- $argv
    or return

    if set -q _flag_install
        if not type -q go
            echo "🚫 maintenance_pc: go is not available on PATH" >&2
            return 1
        end

        set -l repo_dir $HOME/projects/paras-commander

        # Prefer local checkout when available — bypasses Go module proxy
        if test -d $repo_dir/.git
            # Pull latest from remote (fast-forward only — no accidental merge)
            if not git -C $repo_dir pull --ff-only
                echo "🚫 maintenance_pc: git pull failed (local changes in repo?)" >&2
                return 1
            end

            set -l pc_bin (path normalize (go env GOPATH)/bin/pc)
            if not go build -C $repo_dir -o $pc_bin ./cmd/pc
                echo "🚫 maintenance_pc: build failed" >&2
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
                set pc_version (git -C $repo_dir describe --tags --always 2>/dev/null)
            end

            set -l message '🏆 pc updated'
            if test -n "$pc_version"; and test -n "$go_toolchain"
                set message "$message ($pc_version, $go_toolchain)"
            else if test -n "$pc_version"
                set message "$message ($pc_version)"
            else if test -n "$go_toolchain"
                set message "$message ($go_toolchain)"
            end

            if command -v tmux >/dev/null 2>&1
                command tmux display-message "$message" 2>/dev/null
            end

            echo $message >&2
            return 0
        end

        # Fallback: go install @main via direct fetch (for machines without the local checkout)
        # GOPROXY=direct bypasses the module proxy to avoid stale cached module zips
        set -l install_flags -v
        if set -q _flag_force
            set -a install_flags -a
        end

        if not env GOPROXY=direct go install $install_flags github.com/paranoidi/paras-commander/cmd/pc@main
            echo "🚫 maintenance_pc: go install failed" >&2
            return 1
        end

        set -l pc_bin (path normalize (go env GOPATH)/bin/pc)
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

        set -l message '🏆 pc updated'
        if test -n "$pc_version"; and test -n "$go_toolchain"
            set message "$message ($pc_version, $go_toolchain)"
        else if test -n "$pc_version"
            set message "$message ($pc_version)"
        else if test -n "$go_toolchain"
            set message "$message ($go_toolchain)"
        end

        if command -v tmux >/dev/null 2>&1
            command tmux display-message "$message" 2>/dev/null
        end

        echo $message >&2
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

    tsp -L maintenance_pc fish -c (string join ' ' -- $script)
end