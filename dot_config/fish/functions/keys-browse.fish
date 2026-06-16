function keys-browse --description "Browse a keys directory with fzf (section picker → entry search)"
    set -l keys_dir $argv[1]
    set -l prompt $argv[2]
    set -l sections (string replace -r '.*/keys-' '' $keys_dir/keys-*)
    set -l preview_cmd "fish -c 'keys-render $keys_dir/keys-{}'"

    set -l selected (
        printf "%s\n" $sections |
        fzf-tmux \
            -p 90%,80% \
            --ansi \
            --prompt=$prompt \
            --preview=$preview_cmd \
            --preview-window=right:80%:wrap \
            --bind=ctrl-j:preview-page-down \
            --bind=ctrl-k:preview-page-up \
            --preview-label=" Ctrl-j/k: page down/up "
    )
    or return

    keys-render $keys_dir/keys-$selected | fzf-tmux \
        -p 90%,80% \
        --ansi \
        --no-sort \
        --prompt="$selected> " \
        --preview-window=hidden
end
