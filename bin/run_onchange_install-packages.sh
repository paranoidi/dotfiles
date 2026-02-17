#!/bin/bash

# Check and install packages only if they're not already installed
packages_to_install=()
packages=(curl wget git mc task-spooler tmux git-delta fish fd-find bat neovim gh jq unzip)

# Remove packages not available on Debian 11
if [ -f /etc/issue ] && grep -q "Debian GNU/Linux 11" /etc/issue; then
    echo "⚠️  Detected Debian GNU/Linux 11, excluding fish, gh, and git-delta"
    packages=($(printf '%s\n' "${packages[@]}" | grep -v -E '^(fish|gh|git-delta)$'))
fi

for package in "${packages[@]}"; do
    if ! dpkg -l | grep -q "^ii  $package "; then
        packages_to_install+=("$package")
    fi
done

if [ ${#packages_to_install[@]} -gt 0 ]; then
    echo "📦 Installing missing packages: ${packages_to_install[*]}"
    failed_packages=()
    for package in "${packages_to_install[@]}"; do
        echo "  Installing $package..."
        if sudo apt install -y "$package" 2>&1; then
            echo "  ✅ Successfully installed $package"
        else
            echo "  ❌ Failed to install $package (package may not be available)" >&2
            failed_packages+=("$package")
        fi
    done
    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo "⚠️  Warning: The following packages could not be installed: ${failed_packages[*]}" >&2
    fi
else
    echo "✅ All required packages are already installed"
fi

if command -v fd >/dev/null 2>&1; then
    echo "✅ fd command is available"
elif command -v fdfind >/dev/null 2>&1; then
    if [ -x /usr/bin/fdfind ]; then
        if [ -e /usr/local/bin/fd ]; then
            echo "ℹ️  /usr/local/bin/fd already exists"
        else
            echo "🔗 Creating fd symlink for fdfind..."
            sudo ln -s /usr/bin/fdfind /usr/local/bin/fd
            echo "✅ fd symlink created"
        fi
    else
        echo "⚠️  fdfind binary not found at /usr/bin/fdfind, cannot create fd link" >&2
    fi
else
    echo "⚠️  Neither fd nor fdfind is available" >&2
fi

if command -v fzf >/dev/null 2>&1; then
    echo "✅ Fzf is installed"
else
    echo "📦 Installing fzf from github"
    rm -rf ~/.fzf
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --no-bash --no-fish --no-zsh --no-key-bindings --no-completion --no-update-rc
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

if command -v tv >/dev/null 2>&1; then
    echo "📺 tv is available"
else
    echo "📺 Installing tv..."
    curl -fsSL https://alexpasmantier.github.io/television/install.sh | bash
fi

if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
    # These will be executed under graphical environment

    # Install xclip for nvim clipboard integration
    if ! dpkg -l | grep -q "^ii  xclip "; then
        echo "📦 Installing xclip for clipboard integration..."
        sudo apt install -y xclip
    else
        echo "✅ xclip is already installed"
    fi
    if ! dpkg -l | grep -q "^ii  colorized-logs "; then
        echo "📦 Installing colorized-logs for toclip function..."
        sudo apt install -y colorized-logs
    else
        echo "✅ colorized-logs is already installed"
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
fish_path=$(which fish 2>/dev/null)
if [ -z "$fish_path" ]; then
    echo "❌ Error: fish is not installed, cannot change shell" >&2
elif [ "$SHELL" != "$fish_path" ]; then
    # Check fish version (must be at least 3.7)
    fish_version=$(fish --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [ -z "$fish_version" ]; then
        echo "⚠️  Warning: Could not determine fish version, skipping shell change" >&2
    else
        # Compare version (extract major.minor and compare)
        major=$(echo "$fish_version" | cut -d. -f1)
        minor=$(echo "$fish_version" | cut -d. -f2)
        required_major=3
        required_minor=7
        
        if [ "$major" -gt "$required_major" ] || ([ "$major" -eq "$required_major" ] && [ "$minor" -ge "$required_minor" ]); then
            echo "🏆 Changing shell to fish (version $fish_version)..."
            chsh -s "$fish_path"
        else
            echo "⚠️  Warning: fish version $fish_version is less than required 3.7, skipping shell change" >&2
        fi
    fi
fi                                      

