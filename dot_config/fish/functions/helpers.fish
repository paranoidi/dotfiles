function helpers --description 'List user-created and configured helper commands'
    set -l config_home ~/.config
    if set -q XDG_CONFIG_HOME
        set config_home $XDG_CONFIG_HOME
    end

    set -l user_functions_dir (path normalize -- $config_home/fish/functions)
    set -l skipped_functions \
        helpers \
        bat \
        fisher \
        fzf_configure_bindings \
        man \
        nvm

    set -l generated_helpers

    for function_file in (path filter -f -- $user_functions_dir/*.fish)
        set -l helper_name (path change-extension '' (path basename -- $function_file))

        if string match -q '_*' -- $helper_name
            continue
        end

        if contains -- $helper_name $skipped_functions
            continue
        end

        set -l details (functions --details --verbose $helper_name)

        if test (count $details) -lt 5
            continue
        end

        set -l source_path (path normalize -- $details[1])
        set -l description $details[5]

        if test "$source_path" != (path normalize -- $function_file)
            continue
        end

        if test -z "$description"; or test "$description" = n/a
            continue
        end

        if string match -qr '^alias($|\s)' -- $description
            continue
        end

        set -a generated_helpers (printf '%s\t%s' $helper_name $description)
    end

    echo "── Generated helpers ─────────────────────────────────────────────────"
    for helper in (printf '%s\n' $generated_helpers | sort)
        set -l parts (string split --max 1 (printf '\t') -- $helper)
        printf '%-25s %s\n' $parts[1] $parts[2]
    end

    echo ""
    echo "── Manual helpers ────────────────────────────────────────────────────"
    printf '%-25s %s\n' toclip 'send arguments directly to xclip clipboard selection'
    printf '%-25s %s\n' mark 'save the current directory as an fzf mark'
end
