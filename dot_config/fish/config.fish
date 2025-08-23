if status is-interactive
    # Commands to run in interactive sessions can go here
end

# Set Neovim as default editor
set -Ux EDITOR nvim
set -Ux VISUAL nvim
set -Ux GIT_EDITOR nvim

# Point eza to your custom theme
set -x EZA_THEME ~/.config/eza/theme.yml

# Generic binaries
if test -d "$HOME/bin/"
    set -gx fish_user_paths $HOME/bin/ $fish_user_paths
end

# Source local.fish if it exists
if test -f (dirname (status -f))/local.fish
    source (dirname (status -f))/local.fish
end

# Automatically install fisher
if not functions -q fisher
    echo "Installing fisher ..."
    set -q XDG_CONFIG_HOME; or set XDG_CONFIG_HOME ~/.config
    curl https://git.io/fisher --create-dirs -sLo $XDG_CONFIG_HOME/fish/functions/fisher.fish
    fish -c fisher
    fisher_sync
end

# Add helper to install all plugins
function fisher_sync
    for plugin in (cat ~/.config/fish/fish_plugins)
        if not fisher list | grep -qx $plugin
            fisher install $plugin
        end
    end
end

# Use starship prompt if installed
if not set -q CURSOR_AGENT && type -q starship
    starship init fish | source
end

