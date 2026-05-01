# fzf-git integration.
set -l fzf_git_dir ~/.fzf-git
set -l fzf_git_file $fzf_git_dir/fzf-git.fish

if test -f $fzf_git_file
    source $fzf_git_file
else if type -q git
    if not test -d $fzf_git_dir
        echo "🌐 Installing fzf-git ..."
        git clone "https://github.com/junegunn/fzf-git.sh.git" $fzf_git_dir
    end

    if test -f $fzf_git_file
        source $fzf_git_file
    else
        echo "🚫 fzf-git not found after clone attempt: $fzf_git_file" >&2
    end
else
    echo "🚫 Skipping fzf-git setup: git is not available on PATH" >&2
end

# Global fzf options.
# Use Ctrl+P to toggle preview panels instead of Ctrl+/ (hard to type on Finnish keyboard).
set -gx FZF_DEFAULT_OPTS '--cycle --layout=reverse --border --height=90% --preview-window=wrap --marker="*" --bind="ctrl-p:toggle-preview"'

# Override fzf-git's internal wrapper so it uses Ctrl+P for preview toggle too.
set -gx __fzf_git_fzf '
_fzf_git_fzf() {
  fzf --height 50% --tmux 90%,70% \
    --layout reverse --multi --min-height 20+ --border \
    --no-separator --header-border horizontal \
    --border-label-pos 2 \
    --color '\''label:blue'\'' \
    --preview-window '\''right,50%'\'' --preview-border line \
    --bind '\''ctrl-p:change-preview-window(down,50%|hidden|)'\'' "$@"
}
'
