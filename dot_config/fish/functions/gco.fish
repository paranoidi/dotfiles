function gco --description "🔀 git checkout a branch with fzf"
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "🚫 Not in a git repository." >&2
        return 1
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

    git checkout $selected_branch
end
