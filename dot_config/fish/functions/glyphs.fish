function glyphs --description '🎉 Print terminal-friendly glyphs and search them with fzf'
    curl -s "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/glyphnames.json" | jq -r '
        to_entries[]
        | select(.value.char != null)
        | "\(.key)\t\(.value.char)"
    ' | tail +2 | while read -l line
        set -l parts (string split \t -- $line)
        set -l cp (printf '%04x' "'$parts[2]")
        echo "$parts[1] $parts[2] \\u$cp"
    end | fzf --no-mouse
end
