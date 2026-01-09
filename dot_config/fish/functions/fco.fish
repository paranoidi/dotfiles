function fco --description "Git checkout a branch with fzf + tmux"
    git checkout $(git for-each-ref refs/heads/ --format='%(refname:short)' | fzf-tmux)
end
