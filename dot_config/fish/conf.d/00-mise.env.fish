# mise-managed tools and global env (see ~/.config/mise/mise.toml).
# Filename 00- so this runs before fzf/starship conf.d hooks.
if test -x "$HOME/.local/bin/mise"
    $HOME/.local/bin/mise activate fish | source
end
