# Managed by run_onchange_install-packages.sh — mise-managed tools on PATH.
# Filename 00- so this runs before fzf/starship conf.d hooks.
if test -x "$HOME/.local/bin/mise"
    $HOME/.local/bin/mise activate fish | source
end
