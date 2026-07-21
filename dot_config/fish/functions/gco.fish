function gco --description "🔀 git checkout a branch with fzf"
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "🚫 Not in a git repository." >&2
        return 1
    end

    if command -q tv
        tv git-branch
        return
    end

    set -l branches (git for-each-ref refs/heads/ refs/remotes/ --format='%(refname:short)' | grep -v '/HEAD$')
    if test (count $branches) -eq 0
        echo "🚫 No branches found." >&2
        return 1
    end

    set -l log_format '%C(auto)%h%C(reset) %C(cyan)%ad%C(reset) %C(yellow)%d%C(reset) %C(normal)%s%C(reset) %C(dim normal)[%an]%C(reset)'
    set -l preview_cmd "git log --no-show-signature --color=always --date=format:'%Y-%m-%d %H:%M' --pretty=format:"(string escape -- $log_format)" --max-count=100 {}"

    set -l selected_branch (
        printf "%s\n" $branches |
        fzf-tmux \
            --ansi \
            --prompt="git checkout> " \
            --preview=$preview_cmd \
            --preview-window=right:70%:wrap
    )
    or return

    # If the selection is a local branch, just switch to it. Otherwise it's a
    # remote branch (e.g. origin/foo): check out a local tracking branch of the
    # same name instead of ending up in a detached HEAD state.
    if git show-ref --verify --quiet "refs/heads/$selected_branch"
        git switch $selected_branch
    else
        set -l local_name (string replace -r '^[^/]+/' '' -- $selected_branch)
        if git show-ref --verify --quiet "refs/heads/$local_name"
            git switch $local_name
        else
            git switch --track $selected_branch
        end
    end
end
