function g --wraps=git --description '🔀 alias g=git'
    if not type -q git
        echo "🚫 git is not installed"
        return 1
    end
    git $argv
end
