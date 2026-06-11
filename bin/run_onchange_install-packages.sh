#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

# Core packages installed on all systems.
APT_PACKAGES=(
    curl wget git mc task-spooler tmux git-delta
    fish fd-find bat neovim gh jq unzip fastfetch neofetch
    ripgrep silversearcher-ag sysstat
)

# Additional packages installed only on systems with a GUI (X11 / Wayland).
APT_GUI_PACKAGES=(
    phinger-cursor-theme fonts-ubuntu-classic xclip colorized-logs
)

# Go packages installed with `go install`.
GO_PACKAGES=(
    github.com/charmbracelet/gum@latest
)

# Python tools installed with `uv tool install` after uv is available.
UV_TOOLS=(
    tldr
)

# =============================================================================

# Raspberry Pi / Raspberry Pi OS
_is_raspberry_pi() {
    if [[ -r /proc/device-tree/model ]] && tr -d '\0' </proc/device-tree/model | grep -qi 'Raspberry Pi'; then
        return 0
    fi
    if [[ -r /etc/rpi-issue ]]; then
        return 0
    fi
    if [[ -r /etc/os-release ]] && grep -qiE '^(ID=raspbian|ID_LIKE=.*raspbian|PRETTY_NAME=.*Raspberry Pi OS)' /etc/os-release; then
        return 0
    fi
    if uname -a | grep -qiE 'raspberrypi|raspi|bcm27|v[0-9]+\+'; then
        return 0
    fi
    # Fallback for older Raspberry Pi OS installs that report plain Debian.
    [[ -r /etc/issue ]] && grep -q "Debian GNU/Linux 11" /etc/issue
}

IS_RASPI=0
if _is_raspberry_pi; then
    IS_RASPI=1
fi
readonly IS_RASPI


# Filter noisy apt CLI output (stderr is merged where shown).
_apt_out_filter() {
    grep -v -E 'already the newest version|upgraded,|newly installed|to remove|not upgraded|WARNING: apt does not have a stable CLI interface|^Hit:|^Get:|^Ign:|Reading package lists|Building dependency tree|Reading state information|^Fetched |list --upgradable.*see them' | awk 'NF'
}

# Run a sudo apt command; filtered output; return status of apt.
_run_apt() {
    sudo apt "$@" 2>&1 | _apt_out_filter
    return "${PIPESTATUS[0]}"
}

# True iff the named Debian package exists in the current apt cache.
_apt_pkg_is_available() {
    apt-cache show "$1" >/dev/null 2>&1
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

# browser_download_url for an asset on the latest GitHub release (public API; no gh CLI).
# Usage: _github_latest_release_asset_url owner/repo exact_asset_filename
# Optional: GITHUB_TOKEN or GH_TOKEN raises REST rate limits.
_github_latest_release_asset_url() {
    local repo=$1
    local asset_name=$2
    local api_url="https://api.github.com/repos/${repo}/releases/latest"
    local auth=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    elif [[ -n "${GH_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ${GH_TOKEN}")
    fi
    curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: run_onchange-install-packages" \
        "${auth[@]}" \
        "$api_url" \
        | jq -r --arg name "$asset_name" \
            '.assets[] | select(.name == $name) | .browser_download_url' \
        | head -n1
}

install_apt_packages() {
    local packages_to_install=()
    local packages=("${APT_PACKAGES[@]}")
    local gui_packages=("${APT_GUI_PACKAGES[@]}")

    # Only attempt to install GUI-related packages if a graphical session is detected (X11 or Wayland).
    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]] || \
       pgrep -x "Xorg" >/dev/null || \
       pgrep -x "wayland" >/dev/null; then
        packages+=("${gui_packages[@]}")
    fi

    if [[ "$IS_RASPI" == 1 ]]; then
        echo "⚠️  Detected Raspberry Pi OS, excluding fish, gh, and git-delta"
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
        local unavailable_packages=()
        local failed_packages=()
        for package in "${packages_to_install[@]}"; do
            if ! _apt_pkg_is_available "$package"; then
                echo "  ⚠️  Skipping $package (not found in apt cache)" >&2
                unavailable_packages+=("$package")
                continue
            fi
            echo "  ⏳ Installing $package..."
            if _run_apt install -y -qq "$package"; then
                echo "  ✅ Successfully installed $package"
            else
                echo "  ❌ Failed to install $package" >&2
                failed_packages+=("$package")
            fi
        done
        # Redundant with per-package messages
        # if [ ${#unavailable_packages[@]} -gt 0 ]; then
        #     echo "⚠️  Packages not available in apt cache: ${unavailable_packages[*]}" >&2
        # fi
        if [ ${#failed_packages[@]} -gt 0 ]; then
            echo "⚠️  Packages that failed to install: ${failed_packages[*]}" >&2
        fi
    else
        echo "✅ All packages are already installed"
    fi
}

ensure_fd_symlink() {
    # Without --force: satisfied if `fd` is on PATH. With --force: still try fdfind→fd symlink when applicable.
    if command -v fd >/dev/null 2>&1 && [[ "${INSTALL_FORCE:-0}" != 1 ]]; then
        echo "✅ fd"
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
        echo "✅ Fzf"
        return 0
    fi
    echo "🌐 Installing fzf from github"
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
        echo "✅ Starship"
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
        echo "✅ Starship installed successfully"
    else
        echo "❌ Starship installation had issues (exit code: ${starship_exit_code}, or missing success line), but continuing..." >&2
    fi
}

install_eza() {
    if ! _want_install_cmd eza; then
        echo "✅ Eza"
        return 0
    fi
    echo "🔧 Adding eza repository ..."
    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/gierens.gpg
    echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
    sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    _run_apt update -qq
    _run_apt install -y -qq eza
}

install_tv() {
    if ! _want_install_cmd tv; then
        echo "✅ tv"
        return 0
    fi
    if [[ "$IS_RASPI" == 1 ]]; then
        echo "⚠️  tv is not available on Raspberry Pi OS -- or the install script is broken" >&2
        return 1
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

    install_dir=/usr/local/bin
    case "${os}-${m}" in
        Linux-x86_64|Linux-amd64) binary_target=x86_64-unknown-linux-musl ;;
        Linux-aarch64|Linux-arm64) binary_target=aarch64-unknown-linux-gnu ;;
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

install_helix() {
    if ! _want_install_cmd hx; then
        echo "✅ helix"
        return 0
    fi

    local REPO="helix-editor/helix"
    local m os release_json ver
    m="$(uname -m)"
    os="$(uname -s)"

    local auth=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    elif [[ -n "${GH_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ${GH_TOKEN}")
    fi

    release_json=$(curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: run_onchange-install-packages" \
        "${auth[@]}" \
        "https://api.github.com/repos/${REPO}/releases/latest")

    ver=$(printf '%s' "$release_json" | jq -r '.tag_name')
    if [[ -z "$ver" || "$ver" == "null" ]]; then
        echo "❌ Failed to resolve helix release (GitHub API)." >&2
        return 1
    fi

    echo "🌐 Installing helix ${ver}..."

    # On x86_64 Debian/Ubuntu, prefer the official .deb package.
    if [[ "$os" == Linux ]] && command -v apt-get >/dev/null 2>&1 \
       && [[ -f /etc/debian_version ]] && [[ "$m" == "x86_64" ]]; then
        local deb_file deb_url deb_path
        deb_file=$(printf '%s' "$release_json" | jq -r \
            '.assets[] | select(.name | endswith("_amd64.deb")) | .name' | head -n1)
        deb_url=$(printf '%s' "$release_json" | jq -r \
            '.assets[] | select(.name | endswith("_amd64.deb")) | .browser_download_url' | head -n1)
        if [[ -n "$deb_file" && -n "$deb_url" ]]; then
            deb_path=$(mktemp /tmp/helix-XXXXXX.deb)
            echo "⬇️  Downloading ${deb_file}..."
            if curl -fsSL -o "$deb_path" "$deb_url" \
               && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
                  -qq -o Dpkg::Use-Pty=0 "$deb_path"; then
                rm -f "$deb_path"
                echo "✅ helix ${ver} installed"
                return 0
            fi
            rm -f "$deb_path"
            echo "⚠️  .deb install failed, falling back to tarball..." >&2
        fi
    fi

    # Tarball install — covers aarch64 (Raspberry Pi 4/5 with 64-bit OS) and x86_64 fallback.
    # 32-bit ARM (armv7l / armv6l / armv5tel) has no upstream prebuilt binary.
    local asset_suffix
    case "${os}-${m}" in
        Linux-x86_64|Linux-amd64)
            asset_suffix="x86_64-linux.tar.xz" ;;
        Linux-aarch64|Linux-arm64)
            asset_suffix="aarch64-linux.tar.xz" ;;
        Linux-armv7l|Linux-armv6l|Linux-armv5*)
            echo "❌ No prebuilt helix binary for 32-bit ARM (${m})." >&2
            echo "ℹ️  Use 64-bit Raspberry Pi OS (aarch64) for prebuilt binaries." >&2
            echo "ℹ️  Or build from source: https://github.com/${REPO}" >&2
            return 1
            ;;
        *)
            echo "❌ Unsupported OS/arch for helix: ${os} (${m})" >&2
            return 1
            ;;
    esac

    local asset_name="helix-${ver}-${asset_suffix}"
    local asset_url
    asset_url=$(printf '%s' "$release_json" | jq -r --arg name "$asset_name" \
        '.assets[] | select(.name == $name) | .browser_download_url' | head -n1)
    if [[ -z "$asset_url" ]]; then
        echo "❌ No release asset named ${asset_name}" >&2
        return 1
    fi

    # Install to /usr/local/lib/helix/ so the binary finds its runtime directory
    # alongside it (helix resolves runtime relative to its own real path).
    local install_dir="/usr/local/lib/helix"
    local tmpdir
    tmpdir=$(mktemp -d)

    echo "⬇️  Downloading ${asset_name}..."
    if ! curl --progress-bar -L -o "${tmpdir}/${asset_name}" "$asset_url"; then
        rm -rf "$tmpdir"
        return 1
    fi
    tar -xJf "${tmpdir}/${asset_name}" -C "$tmpdir"

    local extracted_dir="${tmpdir}/helix-${ver}-${asset_suffix%.tar.xz}"
    sudo rm -rf "$install_dir"
    sudo mv "$extracted_dir" "$install_dir"
    sudo chmod +x "${install_dir}/hx"
    sudo ln -sf "${install_dir}/hx" /usr/local/bin/hx

    rm -rf "$tmpdir"
    echo "✅ helix ${ver} installed (runtime: ${install_dir}/runtime)"
}

install_amoxide() {
    if [[ "${INSTALL_FORCE:-0}" != 1 ]] && [[ -x "$HOME/.cargo/bin/am" ]]; then
        echo "✅ amoxide"
        return 0
    fi
    echo "🌐 Installing amoxide..."
    if ! curl -fsSL https://github.com/sassman/amoxide-rs/releases/latest/download/amoxide-installer.sh | sh; then
        echo "❌ amoxide installation failed" >&2
        return 1
    fi
    echo "✅ amoxide installed"
}

install_go() {
    if ! _want_install_cmd go; then
        echo "✅ Go"
        return 0
    fi

    echo "🌐 Installing Go..."
    local os arch filename url install_dir install_parent tmpdir
    os=linux
    case "$(uname -m)" in
        x86_64|amd64) arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
        armv7l|armv6l|armv5tel) arch=armv6l ;;
        i386|i686) arch=386 ;;
        *)
            echo "❌ Unsupported machine type for Go: $(uname -m)" >&2
            return 1
            ;;
    esac

    filename=$(curl -fsSL 'https://go.dev/dl/?mode=json' \
        | jq -r --arg suffix ".${os}-${arch}.tar.gz" \
            '.[0].files[] | select(.filename | endswith($suffix)) | .filename' \
        | head -n1)
    if [[ -z "$filename" ]]; then
        echo "❌ Failed to resolve latest Go release for ${os}-${arch}" >&2
        return 1
    fi

    url="https://go.dev/dl/${filename}"
    install_dir="${GO_INSTALL_DIR:-"$HOME/.local/go"}"
    install_parent="$(dirname "$install_dir")"
    tmpdir=$(mktemp -d)
    curl -fsSL -o "${tmpdir}/${filename}" "$url" || { rm -rf "$tmpdir"; return 1; }

    tar -C "$tmpdir" -xzf "${tmpdir}/${filename}"
    rm -rf "$install_dir"
    mkdir -p "$install_parent" "$HOME/.local/bin"
    mv "${tmpdir}/go" "$install_dir"
    rm -rf "$tmpdir"

    ln -sf "${install_dir}/bin/go" "$HOME/.local/bin/go"
    ln -sf "${install_dir}/bin/gofmt" "$HOME/.local/bin/gofmt"
    echo "🐹 $("${install_dir}/bin/go" version)"
}

install_go_packages() {
    local go_cmd
    go_cmd=$(command -v go 2>/dev/null || true)
    if [[ -z "$go_cmd" ]]; then
        local install_dir="${GO_INSTALL_DIR:-"$HOME/.local/go"}"
        if [[ -x "${install_dir}/bin/go" ]]; then
            go_cmd="${install_dir}/bin/go"
        elif [[ -x "$HOME/.local/bin/go" ]]; then
            go_cmd="$HOME/.local/bin/go"
        else
            echo "❌ Go is not available, cannot install Go packages" >&2
            return 1
        fi
    fi

    local gobin="${GO_BIN_DIR:-"$HOME/.local/bin"}"
    mkdir -p "$gobin"

    local package command_name failed_packages=()
    for package in "${GO_PACKAGES[@]}"; do
        command_name="${package%@*}"
        command_name="${command_name##*/}"
        if [[ "${INSTALL_FORCE:-0}" != 1 ]] && { command -v "$command_name" >/dev/null 2>&1 || [[ -x "$gobin/$command_name" ]]; }; then
            echo "✅ ${command_name}"
            continue
        fi

        echo "🐹 Installing ${package}..."
        if GOBIN="$gobin" "$go_cmd" install "$package"; then
            echo "✅ Installed ${command_name}"
        else
            echo "❌ Failed to install ${package}" >&2
            failed_packages+=("$package")
        fi
    done

    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo "⚠️  Go packages that failed to install: ${failed_packages[*]}" >&2
        return 1
    fi
}

_uv_cmd() {
    if command -v uv >/dev/null 2>&1; then
        command -v uv
        return 0
    fi
    if [[ -x "${HOME}/.local/bin/uv" ]]; then
        printf '%s\n' "${HOME}/.local/bin/uv"
        return 0
    fi
    if [[ -x "${HOME}/.cargo/bin/uv" ]]; then
        printf '%s\n' "${HOME}/.cargo/bin/uv"
        return 0
    fi
    return 1
}

install_uv() {
    if ! _want_install_cmd uv; then
        echo "✅ uv"
        return 0
    fi
    echo "🌐 Installing uv (astral)..."
    # Official installer; non-interactive; adds ~/.local/bin/uv by default.
    curl -LsSf https://astral.sh/uv/install.sh | sh
    echo "✅ uv installed"
}

install_uv_tools() {
    local uv_bin tool failed_tools=()
    uv_bin=$(_uv_cmd || true)
    if [[ -z "$uv_bin" ]]; then
        echo "⚠️  uv not on PATH, skipping uv tool installs" >&2
        return 0
    fi
    export PATH="${HOME}/.local/bin:${HOME}/.cargo/bin:${PATH}"

    for tool in "${UV_TOOLS[@]}"; do
        if ! _want_install_cmd "$tool"; then
            echo "✅ ${tool}"
            continue
        fi
        echo "📦 Installing ${tool} via uv..."
        if "$uv_bin" tool install "$tool"; then
            echo "✅ ${tool} installed"
        else
            echo "❌ uv tool install ${tool} failed" >&2
            failed_tools+=("$tool")
        fi
    done

    if [ ${#failed_tools[@]} -gt 0 ]; then
        echo "⚠️  uv tools that failed to install: ${failed_tools[*]}" >&2
        return 1
    fi
}

install_firacode_nerd_font_if_gui() {
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        return 0
    fi
    if [[ "${INSTALL_FORCE:-0}" != 1 ]] && compgen -G "$HOME/.fonts/FiraCodeNerdFont*" > /dev/null; then
        echo "✅ FiraCodeNerdFont"
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
    echo "✅ FiraCodeNerdFont installed"
}

install_jetbrains_mono_font_if_gui() {
    if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
        return 0
    fi
    if [[ "${INSTALL_FORCE:-0}" != 1 ]] && [[ -f "$HOME/.fonts/JetBrainsMono[wght].ttf" ]]; then
        echo "✅ JetBrainsMono"
        return 0
    fi
    echo "🌐 Installing JetBrainsMono..."
    mkdir -p ~/.fonts
    (
        cd /tmp
        wget -q --show-progress -O JetBrainsMono.zip https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip
        unzip -oq -j JetBrainsMono.zip 'fonts/variable/JetBrainsMono\[wght\].ttf' -d ~/.fonts/
        rm -f JetBrainsMono.zip
    )
    fc-cache -f
    echo "✅ JetBrainsMono installed"
}

install_zellij() {
    if ! _want_install_cmd zellij; then
        echo "✅ zellij"
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
        echo "ℹ️ Use 64-bit Raspberry Pi OS, or build from source: https://github.com/${REPO}" >&2
        exit 1
    else
        echo "❌ Unsupported machine type '${_m}' for prebuilt zellij Linux musl." >&2
        echo "ℹ️ Supported: x86_64, aarch64 — https://github.com/${REPO}/releases" >&2
        exit 1
    fi
    local PATTERN="zellij-no-web-${zellij_linux_triple}.tar.gz"
    local REQUIRED_TOOLS=(jq curl tar)

    local tool
    for tool in "${REQUIRED_TOOLS[@]}"; do
      if ! command -v "$tool" >/dev/null 2>&1; then
        echo "❌ Missing required command: ${tool}" >&2
        exit 1
      fi
    done

    mkdir -p "$INSTALL_DIR"

    local URL
    URL="$(_github_latest_release_asset_url "$REPO" "$PATTERN")"

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
      echo "⚠️  Installed zellij in ${INSTALL_DIR}. Unable to determine version."
    fi
}

install_task() {
    if ! _want_install_cmd task; then
        echo "✅ task (taskfile.dev)"
        return 0
    fi
    echo "🔧 Adding taskfile.dev (Cloudsmith) repository..."
    curl -1sLf 'https://dl.cloudsmith.io/public/task/task/setup.deb.sh' | sudo -E bash >/dev/null 2>&1
    _run_apt install -y -qq task
    local ver
    ver=$(task --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    if [[ -n "$ver" ]]; then
        echo "✅ task ${ver} installed"
    else
        echo "✅ task installed"
    fi
}

change_shell_to_fish() {
    local fish_path
    fish_path=$(command -v fish 2>/dev/null || true)
    if [ -z "$fish_path" ]; then
        echo "❌ Fish is not installed, cannot change shell" >&2
        return 0
    fi
    if [ "$SHELL" = "$fish_path" ] && [[ "${INSTALL_FORCE:-0}" != 1 ]]; then
        return 0
    fi
    local fish_version
    fish_version=$(fish --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    if [ -z "$fish_version" ]; then
        echo "❌ Could not determine fish version, skipping shell change" >&2
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
        echo "❌ Fish version $fish_version is less than required 3.7, skipping shell change" >&2
    fi
}

main() {
    echo "🛠️ Install packages ..."
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

    install_apt_packages
    ensure_fd_symlink
    install_uv
    install_uv_tools
    install_fzf
    install_starship
    install_eza
    install_tv
    install_helix
    install_amoxide
    install_go
    install_go_packages
    install_task
    install_firacode_nerd_font_if_gui
    install_jetbrains_mono_font_if_gui
    # install_zellij -- probably sticking with tmux
    change_shell_to_fish
}

main "$@"
