# Ensure user-installed binaries are on PATH before plugin conf.d files run
if test -d "$HOME/bin/"; and not contains -- $HOME/bin/ $fish_user_paths
    set -gx fish_user_paths $HOME/bin/ $fish_user_paths
end

# fzf installed via the upstream install script lives here
if test -d "$HOME/.fzf/bin"; and not contains -- $HOME/.fzf/bin $fish_user_paths
    set -gx fish_user_paths $HOME/.fzf/bin $fish_user_paths
end
