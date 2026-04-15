#!/usr/bin/env bash
set -euo pipefail

# Filter noisy apt CLI output (stderr is merged where shown).
_apt_out_filter() {
    grep -v -E 'already the newest version|upgraded,|newly installed|to remove|not upgraded|WARNING: apt does not have a stable CLI interface|^Hit:|^Get:|^Ign:|Reading package lists|Building dependency tree|Reading state information|^Fetched |list --upgradable.*see them' | awk 'NF'
}

# Run an apt (or sudo apt) command; filtered output; return status of the first pipeline command (apt/sudo).
_run_apt() {
    "$@" 2>&1 | _apt_out_filter
    return "${PIPESTATUS[0]}"
}

# True iff the named Debian package is installed (correct for multiarch :arch names).
_apt_pkg_is_installed() {
    local pkg=$1
    local st
    st=$(dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null) || return 1
    [[ "$st" == "installed" ]]
}

# When INSTALL_FORCE=1, always run installers; otherwise only if the command is missing.
_want_install_cmd() {
    [[ "${INSTALL_FORCE:-0}" == 1 ]] && return 0
    ! command -v "$1" >/dev/null 2>&1
}

# When INSTALL_FORCE=1, always run apt install; otherwise only if the package is not installed.
_want_install_apt_pkg() {
    [[ "${INSTALL_FORCE:-0}" == 1 ]] && return 0
    ! _apt_pkg_is_installed "$1"
}

# Prompt for sudo once up front so password is not requested mid-run.
_require_sudo() {
    if [[ "$(id -u)" -eq 0 ]]; then
        return 0
    fi
    sudo -v
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

    # Raspberry Pi OS
    if [ -f /etc/issue ] && grep -q "Debian GNU/Linux 11" /etc/issue; then
        echo "⚠️  Detected Debian GNU/Linux 11, excluding fish, gh, and git-delta"
        packages=($(printf '%s\n' "${packages[@]}" | grep -v -E '^(fish|gh|git-delta)$'))
    fi

    local package
    for package in "${packages[@]}"; do
        if _want_install_apt_pkg "$package"; then
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
    # Without --force: satisfied if `fd` is on PATH. With --force: still try fdfind→fd symlink when applicable.
    if command -v fd >/dev/null 2>&1 && [[ "${INSTALL_FORCE:-0}" != 1 ]]; then
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
        if command -v fd >/dev/null 2>&1; then
            echo "✅ fd command is available"
        else
            echo "⚠️  Neither fd nor fdfind is available" >&2
        fi
    fi
}

install_fzf() {
    if ! _want_install_cmd fzf; then
        echo "✅ Fzf is installed"
        return 0
    fi
    echo "📦 Installing fzf from github"
    rm -rf ~/.fzf
    git clone -q --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    # Upstream install has no --quiet; curl is invoked without -s, so silence the script output.
    if ! ~/.fzf/install --no-bash --no-fish --no-zsh --no-key-bindings --no-completion --no-update-rc \
        >/dev/null 2>&1; then
        echo "❌ fzf install failed; run ~/.fzf/install manually to see errors" >&2
        return 1
    fi
}

install_starship() {
    if ! _want_install_cmd starship; then
        echo "✅ Starship is available"
        return 0
    fi
    echo "🌐 Installing starship..."
    mkdir -p "${HOME}/.local/bin"
    set +e
    set -o pipefail
    local output
    output=$(curl -fsSL https://starship.rs/install.sh | sh -s -- -y -b "${HOME}/.local/bin" 2>&1)
    local starship_exit_code=$?
    set +o pipefail
    set -e
    if [[ "$starship_exit_code" -eq 0 ]] && printf '%s' "$output" | grep -Fq "Starship latest installed"; then
        echo "🎉 Starship installed successfully"
    else
        echo "❌ Starship installation had issues (exit code: ${starship_exit_code}, or missing success line), but continuing..." >&2
    fi
}

install_eza() {
    if ! _want_install_cmd eza; then
        echo "✅ Eza is available"
        return 0
    fi
    echo "🔧 Adding eza repository ..."
    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    _run_apt sudo apt update -qq
    _run_apt sudo apt install -y -qq eza
}

install_tv() {
    if ! _want_install_cmd tv; then
        echo "✅ tv is available"
        return 0
    fi
    echo "🌐 Installing tv..."
    # Upstream install.sh is chatty (banner, [INFO], curl -LO progress, verbose dpkg).
    # Debian/Ubuntu: download .deb with silent curl and install via apt-get -qq.
    local github_latest='https://api.github.com/repos/alexpasmantier/television/releases/latest'
    local ver os m deb_arch deb_file url deb_path binary_target dirname tarball install_dir tmpdir

    ver=$(curl -fsSL "$github_latest" | grep '"tag_name":' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')
    if [[ -z "$ver" ]]; then
        echo "❌ Failed to resolve television release (GitHub API)." >&2
        return 1
    fi

    os=$(uname -s)
    m=$(uname -m)

    if [[ "$os" == Linux ]] && command -v apt-get >/dev/null 2>&1 && [[ -f /etc/debian_version ]]; then
        case "$m" in
            x86_64|amd64) deb_arch=x86_64-unknown-linux-musl ;;
            aarch64|arm64) deb_arch=aarch64-unknown-linux-gnu ;;
            *)
                echo "❌ No television .deb for architecture ${m}" >&2
                return 1
                ;;
        esac
        deb_file="tv-${ver}-${deb_arch}.deb"
        url="https://github.com/alexpasmantier/television/releases/download/${ver}/${deb_file}"
        deb_path=$(mktemp /tmp/tv-XXXXXX.deb)
        curl -fsSL -o "$deb_path" "$url" || { rm -f "$deb_path"; return 1; }
        if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            -qq -o Dpkg::Use-Pty=0 "$deb_path"; then
            rm -f "$deb_path"
            echo "❌ apt failed to install television .deb" >&2
            return 1
        fi
        rm -f "$deb_path"
        echo "✅ tv ${ver} installed"
        return 0
    fi

    if [[ "$os" == Darwin ]] && command -v brew >/dev/null 2>&1; then
        brew install -q television
        echo "✅ tv installed (Homebrew)"
        return 0
    fi

    install_dir=/usr/local/bin
    case "${os}-${m}" in
        Linux-x86_64|Linux-amd64) binary_target=x86_64-unknown-linux-musl ;;
        Linux-aarch64|Linux-arm64) binary_target=aarch64-unknown-linux-gnu ;;
        Darwin-x86_64) binary_target=x86_64-apple-darwin ;;
        Darwin-arm64) binary_target=aarch64-apple-darwin ;;
        *)
            echo "❌ Unsupported OS/arch for bundled tv installer: ${os} (${m})" >&2
            return 1
            ;;
    esac
    dirname="tv-${ver}-${binary_target}"
    tarball="${dirname}.tar.gz"
    url="https://github.com/alexpasmantier/television/releases/download/${ver}/${tarball}"
    tmpdir=$(mktemp -d)
    curl -fsSL -o "${tmpdir}/${tarball}" "$url" || { rm -rf "$tmpdir"; return 1; }
    tar -xzf "${tmpdir}/${tarball}" -C "$tmpdir"
    sudo mkdir -p "$install_dir"
    sudo mv "${tmpdir}/${dirname}/tv" "${install_dir}/tv"
    sudo chmod +x "${install_dir}/tv"
    rm -rf "$tmpdir"
    echo "✅ tv ${ver} installed"
}

install_xclip_if_gui() {
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        return 0
    fi
    if _want_install_apt_pkg xclip; then
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
    if _want_install_apt_pkg colorized-logs; then
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
    if [[ "${INSTALL_FORCE:-0}" != 1 ]] && compgen -G "$HOME/.fonts/FiraCodeNerdFont*" > /dev/null; then
        echo "✅ FiraCodeNerdFont found"
        return 0
    fi
    echo "🌐 Installing FiraCodeNerdFont..."
    mkdir -p ~/.fonts
    (
        cd /tmp
        wget -q --show-progress -O FiraCode.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/FiraCode.zip
        unzip -oq FiraCode.zip -d ~/.fonts/
        rm -f FiraCode.zip
    )
    fc-cache -f
    echo "✅ FiraCodeNerdFont installed successfully!"
}

install_zellij() {
    if ! _want_install_cmd zellij; then
        echo "✅ zellij is available"
        return 0
    fi
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

    echo "🌐 Downloading ${PATTERN}..."
    curl --progress-bar -L -o "$PATTERN" "$URL"

    echo "💾 Extracting and installing to ${INSTALL_DIR}..."
    tar -xzf "$PATTERN"

    mv zellij "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/zellij"

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
    if [ "$SHELL" = "$fish_path" ] && [[ "${INSTALL_FORCE:-0}" != 1 ]]; then
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
    INSTALL_FORCE=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                INSTALL_FORCE=1
                shift
                ;;
            -h|--help)
                echo "Usage: ${0##*/} [--force] [--help]"
                echo "  --force  Run all installers even when packages/commands already exist"
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Usage: ${0##*/} [--force] [--help]" >&2
                exit 1
                ;;
        esac
    done
    export INSTALL_FORCE

    _require_sudo

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
