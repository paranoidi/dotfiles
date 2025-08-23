#!/bin/bash

sudo apt install curl wget git mc task-spooler tmux git-delta fish fd-find bat fzf neovim gh jq unzip eza

if command -v starship >/dev/null 2>&1; then
    echo "starship is available"
else
    echo "Installing starship"
    set +e  # Temporarily disable exit on error
    curl -sS https://starship.rs/install.sh | sh
    starship_exit_code=$?
    set -e  # Re-enable exit on error
    if [ $starship_exit_code -eq 0 ]; then
        echo "Starship installed successfully"
    else
        echo "Starship installation had issues (exit code: $starship_exit_code), but continuing..."
    fi
fi


if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    # These will be executed under graphical environment

    sudo apt install xclip # nvim clipboard integration
    # Install FiraCode Nerd Font
    if compgen -G "$HOME/.fonts/FiraCodeNerdFont*" > /dev/null; then
        echo "FiraCodeNerdFont found"
    else
        echo "Installing FiraCodeNerdFont..."
        mkdir -p ~/.fonts
        cd /tmp
        wget -O FiraCode.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.zip
        unzip -o FiraCode.zip -d ~/.fonts/
        rm FiraCode.zip
        fc-cache -fv
        echo "FiraCodeNerdFont installed successfully!"
    fi
fi

# Change shell
if [ "$SHELL" != "$(which fish)" ]; then
    echo "Changing shell to fish..."
    chsh -s "$(which fish)"             
fi                                      

