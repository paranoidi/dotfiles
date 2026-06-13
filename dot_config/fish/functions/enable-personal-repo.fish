function enable-personal-repo --description 'Enable personal GitHub SSH remote for the current repo'
    set --local key_path $argv[1]
    set --local alias $argv[2]
    set --local ssh_config "$HOME/.ssh/config"

    if test (count $argv) -gt 2
        echo "🚫 Error: too many arguments."
        echo "Usage: enable-personal-repo <ssh-key-path> <github-host-alias>"
        return 1
    end

    set --local repo_root (git rev-parse --show-toplevel 2>/dev/null)
    set --local current_dir (pwd)

    if test -z "$repo_root"
        echo "🚫 Error: not inside a git repository."
        return 1
    end

    if test "$repo_root" != "$current_dir"
        echo "🚫 Error: must be executed from repository root: $repo_root"
        return 1
    end

    if test -z "$key_path"; or test -z "$alias"
        if not command -q gum
            echo "Usage: enable-personal-repo <ssh-key-path> <github-host-alias>"
            echo "🚫 Error: gum is required when arguments are omitted."
            return 1
        end
    end

    if test -z "$key_path"
        set --local ssh_key_candidates

        for candidate in (path filter -f -- ~/.ssh/*)
            set --local candidate_name (path basename "$candidate")

            switch "$candidate_name"
                case '*.pub' config known_hosts known_hosts.old authorized_keys allowed_signers environment
                    continue
            end

            set --append ssh_key_candidates "$candidate"
        end

        if test (count $ssh_key_candidates) -eq 0
            echo "🚫 Error: no SSH key candidates found in ~/.ssh"
            return 1
        end

        set key_path (printf '%s\n' $ssh_key_candidates | gum choose --header "Select SSH key")

        if test -z "$key_path"
            echo "🚫 Error: no SSH key selected."
            return 1
        end
    end

    if test -z "$alias"
        set --local alias_candidates github-personal

        if test -f "$ssh_config"
            for line in (string match --regex '^\s*Host\s+.+$' < "$ssh_config")
                for host in (string split ' ' -- (string replace --regex '^\s*Host\s+' '' -- "$line"))
                    if test -z "$host"
                        continue
                    end

                    if string match --quiet --regex '[\*\?]' -- "$host"
                        continue
                    end

                    if not string match --quiet 'github*' -- "$host"
                        continue
                    end

                    if not contains -- "$host" $alias_candidates
                        set --append alias_candidates "$host"
                    end
                end
            end
        end

        set alias (printf '%s\n' $alias_candidates | gum choose --header "Select GitHub host alias")

        if test -z "$alias"
            echo "🚫 Error: no GitHub host alias selected."
            return 1
        end
    end

    set --local origin_url (git config --get remote.origin.url)

    if test -z "$origin_url"
        echo "🚫 Error: no remote.origin.url found"
        return 1
    end

    set --local owner_repo (string replace --regex '.*github\.com[:/]+' '' -- "$origin_url" | string replace --regex '.*github-[a-z0-9]+[:/]+' '' | string replace --regex '\.git$' '')
    set --local owner (string split --max 1 / -- "$owner_repo")[1]
    set --local repo (string split --max 1 / -- "$owner_repo")[2]

    if test -z "$owner"; or test -z "$repo"
        echo "🚫 Error: failed to parse owner/repo from origin URL: $origin_url"
        return 1
    end

    echo "Detected repo:"
    echo "  Owner: $owner"
    echo "  Repo : $repo"

    if not test -f "$key_path"
        echo "🚫 Error: SSH key not found at $key_path"
        return 1
    end

    if not grep -q -- '-----BEGIN.*PRIVATE KEY' "$key_path" 2>/dev/null
        echo (wide_emoji "⚠️")"Warning: $key_path may not be a valid SSH private key."
    end

    mkdir -p (dirname "$ssh_config")
    touch "$ssh_config"

    set --local escaped_alias (string escape --style=regex -- "$alias")
    set --local block_exists 0
    set --local block_key ""
    set --local in_target_block 0

    while read -l config_line
        if string match --quiet --regex "^Host\\s+$escaped_alias\$" -- "$config_line"
            set in_target_block 1
            set block_exists 1
        else if test $in_target_block -eq 1
            if string match --quiet --regex '^Host\s' -- "$config_line"
                set in_target_block 0
            else if string match --quiet --regex '^\s*IdentityFile\s' -- "$config_line"
                set block_key (string replace --regex '^\s*IdentityFile\s+' '' -- "$config_line")
            end
        end
    end < "$ssh_config"

    if test $block_exists -eq 0
        begin
            echo ''
            echo "Host $alias"
            echo '  HostName github.com'
            echo '  User git'
            echo "  IdentityFile $key_path"
            echo '  IdentitiesOnly yes'
        end >> "$ssh_config"
    else if test "$block_key" != "$key_path"
        echo "Updating IdentityFile for '$alias' from: $block_key"
        echo "                                      to: $key_path"
        sed -i -E "/^Host[[:space:]]+$alias$/,/^Host[[:space:]]/ s|^([[:space:]]*IdentityFile[[:space:]]+).*|\1$key_path|" "$ssh_config"
    else
        echo "SSH alias '$alias' already exists in config with correct key."
    end

    set --local new_url "git@$alias:$owner/$repo.git"

    if test "$origin_url" = "$new_url"
        echo "Origin is already set to: $new_url"
    else
        echo "Updating origin from: $origin_url"
        echo "             to: $new_url"
        git remote set-url origin "$new_url"
    end

    git config user.name "paranoidi"
    git config user.email "marko.koivusalo@gmail.com"

    echo "Done."
end
