function glyphs --description '🎉 Print terminal-friendly glyphs and search them with fzf'
    curl -s "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/glyphnames.json" | jq -r 'to_entries[] | "\(.key) \(.value.char)"' | tail +2 | fzf --no-mouse
end
