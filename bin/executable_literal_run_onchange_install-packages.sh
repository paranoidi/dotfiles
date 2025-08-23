#!/bin/bash

sudo apt install git mc task-spooler tmux git-delta fish fd-find bat fzf neovim gh jq unzip

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
