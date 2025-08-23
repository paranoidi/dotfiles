#!/bin/bash

# Check and install packages only if they're not already installed
packages_to_install=()
packages=(curl wget git mc task-spooler tmux git-delta fish fd-find bat fzf neovim gh jq unzip)

for package in "${packages[@]}"; do
    if ! dpkg -l | grep -q "^ii  $package "; then
        packages_to_install+=("$package")
    fi
done

if [ ${#packages_to_install[@]} -gt 0 ]; then
    echo "📦 Installing missing packages: ${packages_to_install[*]}"
    sudo apt install -y "${packages_to_install[@]}"
else
    echo "✅ All required packages are already installed"
fi

if command -v starship >/dev/null 2>&1; then
    echo "🚀 Starship is available"
else
    echo "🚀 Installing starship..."
    set +e  # Temporarily disable exit on error
    curl -sS https://starship.rs/install.sh | sh
    starship_exit_code=$?
    set -e  # Re-enable exit on error
    if [ $starship_exit_code -eq 0 ]; then
        echo "🎉 Starship installed successfully"
    else
        echo "❌ Starship installation had issues (exit code: $starship_exit_code), but continuing..."
    fi
fi

if command -v eza >/dev/null 2>&1; then
    echo "🎉 Eza is available"
else
    echo "📦 Installing eza..."
    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    sudo apt update
    sudo apt install -y eza
fi

if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    # These will be executed under graphical environment

    # Install xclip for nvim clipboard integration
    if ! dpkg -l | grep -q "^ii  xclip "; then
        echo "📦 Installing xclip for nvim clipboard integration..."
        sudo apt install -y xclip
    else
        echo "✅ xclip is already installed"
    fi
    # Install FiraCode Nerd Font
    if compgen -G "$HOME/.fonts/FiraCodeNerdFont*" > /dev/null; then
        echo "🌟 FiraCodeNerdFont found"
    else
        echo "📦 Installing FiraCodeNerdFont..."
        mkdir -p ~/.fonts
        cd /tmp
        wget -O FiraCode.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.zip
        unzip -o FiraCode.zip -d ~/.fonts/
        rm FiraCode.zip
        fc-cache -fv
        echo "🎉 FiraCodeNerdFont installed successfully!"
    fi
fi

# Change shell
if [ "$SHELL" != "$(which fish)" ]; then
    echo "🏆 Changing shell to fish..."
    chsh -s "$(which fish)"             
fi                                      

