# Bootstrap Python tooling for interactive shells.
if status is-interactive; and command -q uv
    if not command -q tldr
        if command -q tsp
            echo "📦 Installing tldr in the background"
            tsp fish -c "uv tool install tldr" > /dev/null
        else
            _spinner --fallback-prefix "🐍" "Installing tldr ..." uv tool install tldr
        end
    end
end
