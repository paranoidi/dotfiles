function t --wraps=task --description 'alias t=task'
    if not type -q task
        echo "🚫 task is not installed"
        return 1
    end
    task $argv
end
