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

# Source local.fish if it exists
if test -f (dirname (status -f))/local.fish
    source (dirname (status -f))/local.fish
end

set -q XDG_CONFIG_HOME; or set -gx XDG_CONFIG_HOME ~/.config
set -l fisher_file $XDG_CONFIG_HOME/fish/functions/fisher.fish

# Add helper to install all plugins
function fisher_sync
    if set -q __fisher_sync_running
        return
    end

    if not test -f ~/.config/fish/fish_plugins
        return
    end

    if not functions -q fisher
        if test -f $XDG_CONFIG_HOME/fish/functions/fisher.fish
            source $XDG_CONFIG_HOME/fish/functions/fisher.fish
        else
            return
        end
    end

    set -gx __fisher_sync_running 1

    for plugin in (string match -rv '^\s*(#|$)' < ~/.config/fish/fish_plugins)
        if not fisher list | grep -qx -- $plugin
            fisher install $plugin
        end
    end

    set -e __fisher_sync_running
end

# Automatically install fisher and plugins only for interactive shells
if status is-interactive; and not set -q __fisher_sync_running
    if not type -q fzf
        echo "🚫 Skipping fisher bootstrap: fzf is not available on PATH" >&2
    else
        if not test -f $fisher_file
            echo "Installing fisher ..."
            curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish --create-dirs -o $fisher_file
        end

        if not functions -q fisher
            source $fisher_file
        end

        fisher_sync
    end
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
      #tsp fish -c "nvm use latest && npm install -g @mariozechner/pi-coding-agent" > /dev/null
      # Let's keep JS stuff 7 days old since they can't keep their supplychain secure
      tsp fish -c "nvm use latest && npm install --min-release-age=7 -g @mariozechner/pi-coding-agent" > /dev/null
  else
      echo "🚫 nvm is not installed on this machine"
  end
end

function update_fzf
    if type -q fzf
      cd ~/.fzf/
      git pull
      ~/.fzf/install --no-bash --no-fish --no-zsh --no-key-bindings --no-completion --no-update-rc
    else
      echo "🚫 fzf is not installed on this machine"
    end
end

function check_and_run_periodic
    # Cache directory
    set -l cache_dir ~/.cache/fish
    set -l daily_file $cache_dir/last_daily_run
    set -l weekly_file $cache_dir/last_weekly_run

    # Ensure cache directory exists
    if not test -d $cache_dir
        mkdir -p $cache_dir
    end

    set -l current_time (date +%s)

    # ---- DAILY CHECK ----
    set -l run_daily false

    if test -f $daily_file
        set -l last_run (cat $daily_file)
        set -l diff (math $current_time - $last_run)

        if test $diff -ge 86400
            set run_daily true
        end
    else
        set run_daily true
    end

    if test "$run_daily" = "true"
        echo "Running DAILY tasks at "(date)
        purgehist
        update_pi
        echo $current_time > $daily_file
    end

    # ---- WEEKLY CHECK ----
    set -l run_weekly false

    if test -f $weekly_file
        set -l last_run (cat $weekly_file)
        set -l diff (math $current_time - $last_run)

        if test $diff -ge 604800  # 7 days
            set run_weekly true
        end
    else
        set run_weekly true
    end

    if test "$run_weekly" = "true"
        echo "Running WEEKLY tasks at "(date)
        update_fzf
        echo $current_time > $weekly_file
    end
end

# Run daily check in interactive sessions
if status is-interactive
    check_and_run_periodic
end

# Use starship prompt if installed
if not set -q CURSOR_AGENT && type -q starship
    starship init fish | source
end

# Enable direnv
if type -q direnv
    eval (direnv hook fish)
end
