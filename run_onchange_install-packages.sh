#!/bin/bash

sudo apt install git mc task-spooler tmux git-delta fish fd-find bat fzf neovim gh jq

if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    sudo apt install xclip # nvim clipboard integration
fi
