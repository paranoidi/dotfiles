function fco
    git checkout $(git for-each-ref refs/heads/ --format='%(refname:short)' | fzf-tmux)
end
