function copy-chezmoi-key --description 'Copy the shared chezmoi age key to a remote machine over ssh'
    argparse f/force -- $argv
    or return

    if test (count $argv) -ne 1
        echo "Usage: copy-chezmoi-key [-f|--force] <host>" >&2
        return 1
    end

    set -l host $argv[1]
    set -l key ~/.config/chezmoi/key.txt

    if not test -f $key
        echo "🚫 copy-chezmoi-key: $key not found locally" >&2
        return 1
    end

    if not set -q _flag_force
        if ssh $host 'test -f ~/.config/chezmoi/key.txt' 2>/dev/null
            echo "⚠️  $host already has ~/.config/chezmoi/key.txt — use --force to overwrite" >&2
            return 1
        end
    end

    ssh $host 'mkdir -p ~/.config/chezmoi'
    or return 1

    scp -pq $key "$host:.config/chezmoi/key.txt"
    or return 1

    ssh $host 'chmod 600 ~/.config/chezmoi/key.txt'
    or return 1

    echo "✅ copied chezmoi age key to $host:~/.config/chezmoi/key.txt"
end
