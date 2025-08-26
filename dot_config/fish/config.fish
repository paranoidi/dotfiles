if status is-interactive
    # Commands to run in interactive sessions can go here
end

# Fix locales
set -Ux LANG en_US.UTF-8
set -Ux LC_ALL en_US.UTF-8

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

# Add helper to install all plugins
function fisher_sync
    for plugin in (cat ~/.config/fish/fish_plugins)
        if not fisher list | grep -qx $plugin
            fisher install $plugin
        end
    end
end

# Automatically install fisher
if not functions -q fisher
    echo "Installing fisher ..."
    set -q XDG_CONFIG_HOME; or set XDG_CONFIG_HOME ~/.config
    curl https://git.io/fisher --create-dirs -sLo $XDG_CONFIG_HOME/fish/functions/fisher.fish
    fish -c fisher
    fisher_sync
end

# Classic fzf-style keybindings in fish
if functions -q fzf_configure_bindings
    # Ctrl+T → insert file path
    function fzf_insert_file
        set file (_fzf_search_directory)
        if test -n "$file"
            commandline -i -- $file
        end
    end
    bind \cT fzf_insert_file

    # Alt+C → cd into directory
    function fzf_cd
        set dir (_fzf_search_directory)
        if test -n "$dir"
            cd $dir
            commandline -f repaint
        end
    end
    bind \ec fzf_cd

    # Ctrl+R → fuzzy history (already bound, but ensure in insert mode too)
    bind \cr _fzf_search_history
    bind -M insert \cr _fzf_search_history

    # Ctrl+P → fuzzy process picker (kills selected PID)
    function fzf_kill_process
        set pid (_fzf_search_processes)
        if test -n "$pid"
            echo "Killing process $pid"
            kill -9 $pid
        end
    end
    bind \cP fzf_kill_process
end

# Disable history for commands that cursor runs
if set -q CURSOR_AGENT
    set -U HISTFILE /dev/null
end

# Use starship prompt if installed
if not set -q CURSOR_AGENT && type -q starship
    starship init fish | source
end

