function keys --description "🔑 Browse keyboard shortcuts with fzf"
    set -l keys_dir ~/.config/fish/keys
    set -l sections (string replace -r '.*/keys-' '' $keys_dir/keys-*)
    set -l preview_cmd "cat $keys_dir/keys-{}"

    set -l selected (
        printf "%s\n" $sections |
        fzf-tmux \
            --ansi \
            --prompt="keys> " \
            --preview=$preview_cmd \
            --preview-window=right:60%:wrap
    )
    or return

    cat $keys_dir/keys-$selected
end
