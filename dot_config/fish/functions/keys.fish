function keys --description "🔑 Browse keyboard shortcuts with fzf"
    set -l dir (dirname (status filename))
    set -l sections (string replace -r '.*/keys-' '' (string replace '.fish' '' $dir/keys-*.fish))
    set -l preview_cmd "fish -c keys-{}"

    set -l selected (
        printf "%s\n" $sections |
        fzf-tmux \
            --ansi \
            --prompt="keys> " \
            --preview=$preview_cmd \
            --preview-window=right:60%:wrap
    )
    or return

    fish -c keys-$selected
end
