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
    if not type -q fisher
        return
    end

    if not test -f ~/.config/fish/fish_plugins
        return
    end

    for plugin in (string match -rv '^\s*(#|$)' < ~/.config/fish/fish_plugins)
        if not fisher list | grep -qx -- $plugin
            fisher install $plugin
        end
    end
end

# Automatically install fisher
if not type -q fisher
    echo "Installing fisher ..."
    set -q XDG_CONFIG_HOME; or set -gx XDG_CONFIG_HOME ~/.config
    curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish --create-dirs -o $XDG_CONFIG_HOME/fish/functions/fisher.fish
    source $XDG_CONFIG_HOME/fish/functions/fisher.fish
end

fisher_sync

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

# Remove Alt-PgUp/Down crap
bind \e\[5\;3\~ ''
bind \e\[6\;3\~ ''

# Disable history when cursor agent is running
if set -q CURSOR_AGENT
    set -g fish_history ""
end

# Daily maintenance operations
function purgehist
    tsp rmhist -s '^(sgpt|aichat|git commit)' > /dev/null
    tsp rmhist -s '^(ls|cd\s\.\.)$' > /dev/null
end

function update_pi
  if type -q nvm
      tsp fish -c "nvm use latest && npm install -g @mariozechner/pi-coding-agent" > /dev/null
  else
      echo "🚫 nvm is not installed on this machine"
  end
end

function check_and_run_daily
    # Store timestamp in ~/.cache/fish/
    set -l cache_dir ~/.cache/fish
    set -l timestamp_file $cache_dir/last_daily_run
    
    # Create cache directory if it doesn't exist
    if not test -d $cache_dir
        mkdir -p $cache_dir
    end
    
    set -l current_time (date +%s)
    set -l should_run false
    
    # Check if timestamp file exists
    if test -f $timestamp_file
        set -l last_run (cat $timestamp_file)
        # Calculate time difference in seconds (24 hours = 86400 seconds)
        set -l time_diff (math $current_time - $last_run)
        
        if test $time_diff -ge 86400
            set should_run true
        end
    else
        # First run, no timestamp file exists
        set should_run true
    end
    
    # Run the function and update timestamp
    if test "$should_run" = "true"
        echo "Running daily tasks in background at "(date)
        purgehist
        update_pi
        echo $current_time > $timestamp_file
    end
end

# Run daily check in interactive sessions
if status is-interactive
    check_and_run_daily
end

# Use starship prompt if installed
if not set -q CURSOR_AGENT && type -q starship
    starship init fish | source
end

# Enable direnv
if type -q direnv
    eval (direnv hook fish)
end
