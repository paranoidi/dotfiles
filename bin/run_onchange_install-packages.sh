#!/usr/bin/env bash
set -euo pipefail

# Filter noisy apt CLI output (stderr is merged where shown).
_apt_out_filter() {
    grep -v -E 'already the newest version|upgraded,|newly installed|to remove|not upgraded|WARNING: apt does not have a stable CLI interface' | awk 'NF'
}

# Run an apt (or sudo apt) command; filtered output; return status of the first pipeline command (apt/sudo).
_run_apt() {
    "$@" 2>&1 | _apt_out_filter
    return "${PIPESTATUS[0]}"
}

install_apt_packages() {
    local packages_to_install=()
    local packages=(curl wget git mc task-spooler tmux git-delta fish fd-find bat neovim gh jq unzip)
    local gui_packages=(phinger-cursor-theme fonts-ubuntu-classic)

    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]] || \
       pgrep -x "Xorg" >/dev/null || \
       pgrep -x "wayland" >/dev/null; then
        packages+=("${gui_packages[@]}")
    fi

    if [ -f /etc/issue ] && grep -q "Debian GNU/Linux 11" /etc/issue; then
        echo "⚠️  Detected Debian GNU/Linux 11, excluding fish, gh, and git-delta"
        packages=($(printf '%s\n' "${packages[@]}" | grep -v -E '^(fish|gh|git-delta)$'))
    fi

    local package
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            packages_to_install+=("$package")
        fi
    done

    if [ ${#packages_to_install[@]} -gt 0 ]; then
        echo "📦 Installing packages: ${packages_to_install[*]}"
        local failed_packages=()
        for package in "${packages_to_install[@]}"; do
            echo "  ⏳ Installing $package..."
            if _run_apt sudo apt install -y -qq "$package"; then
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
}

ensure_fd_symlink() {
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
}

install_fzf() {
    if command -v fzf >/dev/null 2>&1; then
        echo "✅ Fzf is installed"
        return 0
    fi
    echo "📦 Installing fzf from github"
    rm -rf ~/.fzf
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --no-bash --no-fish --no-zsh --no-key-bindings --no-completion --no-update-rc
}

install_starship() {
    if command -v starship >/dev/null 2>&1; then
        echo "🚀 Starship is available"
        return 0
    fi
    echo "🚀 Installing starship..."
    set +e
    curl -sS https://starship.rs/install.sh -y | sh
    local starship_exit_code=$?
    set -e
    if [ $starship_exit_code -eq 0 ]; then
        echo "🎉 Starship installed successfully"
    else
        echo "❌ Starship installation had issues (exit code: $starship_exit_code), but continuing..."
    fi
}

install_eza() {
    if command -v eza >/dev/null 2>&1; then
        echo "🎉 Eza is available"
        return 0
    fi
    echo "📦 Installing eza..."
    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    _run_apt sudo apt update
    _run_apt sudo apt install -y -qq eza
}

install_tv() {
    if command -v tv >/dev/null 2>&1; then
        echo "📺 tv is available"
        return 0
    fi
    echo "📺 Installing tv..."
    curl -fsSL https://alexpasmantier.github.io/television/install.sh | bash
}

install_xclip_if_gui() {
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        return 0
    fi
    if ! dpkg -l | grep -q "^ii  xclip "; then
        echo "📦 Installing xclip for clipboard integration..."
        _run_apt sudo apt install -y -qq xclip
    else
        echo "✅ xclip is already installed"
    fi
}

install_colorized_logs_if_gui() {
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        return 0
    fi
    if ! dpkg -l | grep -q "^ii  colorized-logs "; then
        echo "📦 Installing colorized-logs for toclip function..."
        _run_apt sudo apt install -y -qq colorized-logs
    else
        echo "✅ colorized-logs is already installed"
    fi
}

install_firacode_nerd_font_if_gui() {
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        return 0
    fi
    if compgen -G "$HOME/.fonts/FiraCodeNerdFont*" > /dev/null; then
        echo "🌟 FiraCodeNerdFont found"
        return 0
    fi
    echo "📦 Installing FiraCodeNerdFont..."
    mkdir -p ~/.fonts
    (
        cd /tmp
        wget -O FiraCode.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.zip
        unzip -o FiraCode.zip -d ~/.fonts/
        rm FiraCode.zip
    )
    fc-cache -fv
    echo "🎉 FiraCodeNerdFont installed successfully!"
}

install_zellij() {
    local INSTALL_DIR="${INSTALL_DIR:-"$HOME/.local/bin"}"
    local REPO="zellij-org/zellij"

    local zellij_linux_triple
    local _m
    _m="$(uname -m)"
    if [ "$_m" = "x86_64" ]; then
        zellij_linux_triple="x86_64-unknown-linux-musl"
    elif [ "$_m" = "aarch64" ] || [ "$_m" = "arm64" ]; then
        zellij_linux_triple="aarch64-unknown-linux-musl"
    elif [ "$_m" = "armv7l" ] || [ "$_m" = "armv6l" ] || [ "$_m" = "armv5tel" ]; then
        echo "❌ zellij does not publish 32-bit ARM Linux binaries (machine: ${_m})." >&2
        echo "ℹ️  Use 64-bit Raspberry Pi OS, or build from source: https://github.com/${REPO}" >&2
        exit 1
    else
        echo "❌ Unsupported machine type '${_m}' for prebuilt zellij Linux musl." >&2
        echo "ℹ️  Supported: x86_64, aarch64 — https://github.com/${REPO}/releases" >&2
        exit 1
    fi
    local PATTERN="zellij-no-web-${zellij_linux_triple}.tar.gz"
    local REQUIRED_TOOLS=(gh jq curl tar)

    echo "🤔 Installing zellij for ${zellij_linux_triple}"

    local tool
    for tool in "${REQUIRED_TOOLS[@]}"; do
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ Missing required command: ${tool}" >&2
        exit 1
      fi
    done

    mkdir -p "$INSTALL_DIR"

    local URL
    URL="$(gh api "repos/$REPO/releases/latest" --jq \
      ".assets[] | select(.name == \"$PATTERN\") | .browser_download_url")"

    if [[ -z "$URL" ]]; then
      echo "❌ No release asset named ${PATTERN}" >&2
      exit 1
    fi

    echo ""
    echo "🌐 Downloading ${PATTERN}..."
    curl --progress-bar -L -o "$PATTERN" "$URL"
    echo ""

    echo "💾 Extracting and installing to ${INSTALL_DIR}..."
    tar -xzf "$PATTERN"

    mv zellij "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/zellij"

    echo "💀 Removing ${PATTERN}..."
    rm "$PATTERN"

    local ver
    ver="$("$INSTALL_DIR/zellij" --version 2>/dev/null || true)"
    if [[ -n "$ver" ]]; then
      echo "✅ Installed ${ver}"
    else
      echo "⚠️ Installed zellij in ${INSTALL_DIR}. Unable to determine version."
    fi
}

change_shell_to_fish() {
    local fish_path
    fish_path=$(command -v fish 2>/dev/null || true)
    if [ -z "$fish_path" ]; then
        echo "❌ Error: fish is not installed, cannot change shell" >&2
        return 0
    fi
    if [ "$SHELL" = "$fish_path" ]; then
        return 0
    fi
    local fish_version
    fish_version=$(fish --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [ -z "$fish_version" ]; then
        echo "⚠️  Warning: Could not determine fish version, skipping shell change" >&2
        return 0
    fi
    local major minor
    major=$(echo "$fish_version" | cut -d. -f1)
    minor=$(echo "$fish_version" | cut -d. -f2)
    local required_major=3
    local required_minor=7

    if [ "$major" -gt "$required_major" ] || ([ "$major" -eq "$required_major" ] && [ "$minor" -ge "$required_minor" ]); then
        echo "🏆 Changing shell to fish (version $fish_version)..."
        chsh -s "$fish_path"
    else
        echo "⚠️  Warning: fish version $fish_version is less than required 3.7, skipping shell change" >&2
    fi
}

main() {
    install_apt_packages
    ensure_fd_symlink
    install_fzf
    install_starship
    install_eza
    install_tv
    install_xclip_if_gui
    install_colorized_logs_if_gui
    install_firacode_nerd_font_if_gui
    install_zellij
    change_shell_to_fish
}

main "$@"
