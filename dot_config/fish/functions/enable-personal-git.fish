function enable-personal-git --description 'Set up the personal git identity and GitHub SSH key on this machine'
    set --local key_path $argv[1]
    set --local local_config "$HOME/.gitconfig.local"
    set --local ssh_dir "$HOME/.ssh"
    set --local ssh_config "$ssh_dir/config"
    set --local default_key "$ssh_dir/id_ed25519_github"

    if test (count $argv) -gt 1
        echo "🚫 Error: too many arguments."
        echo "Usage: enable-personal-git [ssh-key-path]"
        return 1
    end

    # Identity. ~/.gitconfig (chezmoi) includes ~/.gitconfig.local, which stays machine-local.
    # Re-running only rewrites these keys, so any other local settings are kept.
    git config --file "$local_config" user.name paranoidi
    git config --file "$local_config" user.email marko.koivusalo@gmail.com
    # The first push of a new branch sets up its upstream instead of failing.
    git config --file "$local_config" push.autoSetupRemote true
    echo "Wrote identity and push.autoSetupRemote to $local_config"

    # SSH key: argument, else the conventional name, else pick one from ~/.ssh.
    if test -z "$key_path"
        if test -f "$default_key"
            set key_path "$default_key"
        else
            set --local candidates
            for candidate in (path filter -f -- $ssh_dir/*)
                switch (path basename "$candidate")
                    case '*.pub' config known_hosts known_hosts.old authorized_keys allowed_signers environment
                        continue
                end
                set --append candidates "$candidate"
            end

            if test (count $candidates) -eq 0
                echo "🚫 Error: no SSH key found in $ssh_dir"
                echo "Create one with: ssh-keygen -t ed25519 -f $default_key"
                return 1
            else if test (count $candidates) -eq 1
                set key_path $candidates[1]
            else if command -q fzf
                set key_path (printf '%s\n' $candidates | fzf --prompt "SSH key> " --height 60% --reverse --header "Select the GitHub SSH key" --preview 'ssh-keygen -l -f {}.pub 2>/dev/null || ssh-keygen -l -f {} 2>/dev/null; echo; cat {}.pub 2>/dev/null' --preview-window 'right:60%:wrap')
                if test -z "$key_path"
                    echo "🚫 Error: no SSH key selected."
                    return 1
                end
            else
                echo "🚫 Error: several SSH keys in $ssh_dir; pass one: enable-personal-git <ssh-key-path>"
                return 1
            end
        end
    end

    if not test -f "$key_path"
        echo "🚫 Error: SSH key not found at $key_path"
        return 1
    end
    if not grep -q -- '-----BEGIN.*PRIVATE KEY' "$key_path" 2>/dev/null
        echo (wide_emoji "⚠️")"Warning: $key_path may not be a valid SSH private key."
    end

    # ssh refuses keys and configs that others can read.
    chmod 700 "$ssh_dir"
    chmod 600 "$key_path"
    touch "$ssh_config"
    chmod 600 "$ssh_config"

    # ~/.ssh/config: without it ssh only offers id_rsa / id_ed25519 / ..., never a custom name.
    # A "Host github.com" block gets exactly this IdentityFile plus IdentitiesOnly; the rest of
    # the block (and the file) is kept.
    if string match --quiet --regex '^\s*Host\s+github\.com\s*$' < "$ssh_config"
        set --local tmp (mktemp)
        awk -v key="$key_path" '
            /^[ \t]*(Host|Match)[ \t]/ { inblock = ($0 ~ /^[ \t]*Host[ \t]+github\.com[ \t]*$/) }
            inblock && /^[ \t]*(IdentityFile|IdentitiesOnly)[ \t]/ { next }
            { print }
            inblock && /^[ \t]*Host[ \t]/ { print "  IdentityFile " key; print "  IdentitiesOnly yes" }
        ' "$ssh_config" > "$tmp"
        and cat "$tmp" > "$ssh_config"
        rm -f "$tmp"
        echo "Updated the github.com block in $ssh_config to use $key_path"
    else
        begin
            echo ''
            echo 'Host github.com'
            echo '  HostName github.com'
            echo '  User git'
            echo "  IdentityFile $key_path"
            echo '  IdentitiesOnly yes'
        end >> "$ssh_config"
        echo "Added a github.com block to $ssh_config using $key_path"
    end

    # Check that GitHub accepts the key (accept-new records GitHub's host key on first use).
    set --local reply (ssh -T -o BatchMode=yes -o StrictHostKeyChecking=accept-new git@github.com 2>&1)
    if string match --quiet '*successfully authenticated*' -- $reply
        echo "✅ "(string match --regex 'Hi [^!]+!' -- $reply)" GitHub accepts $key_path"
    else
        echo (wide_emoji "⚠️")"Warning: GitHub did not accept the key:"
        printf '  %s\n' $reply
        echo "Is $key_path.pub added at https://github.com/settings/keys ?"
        return 1
    end
end
