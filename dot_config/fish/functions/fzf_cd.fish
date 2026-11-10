function fzf_cd --description "cd into a subdirectory picked with fzf"
    if not type -q fzf; or not type -q fd
        echo "🚫 fzf_cd requires fzf and fd" >&2
        return 1
    end
    set -l dir (command fd --type d --hidden --exclude .git | fzf --prompt "cd> " --preview 'ls -A --color=always {}')
    and cd -- $dir
    commandline -f repaint
end
