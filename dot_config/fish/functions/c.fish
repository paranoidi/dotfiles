function c --wraps=claude --description '🤖 alias c=claude'
    if not type -q claude
        echo "🚫 claude is not installed"
        return 1
    end
    claude $argv
end
