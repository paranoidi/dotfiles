#!/usr/bin/env bash
set -euo pipefail

# If not already inside tmux but tmux is available, relaunch inside a tmux
# window so the terminal is freed for the duration of the (potentially long)
# installation.  Prefer an existing "main" session; fall back to a new session
# named "genesis".
if [[ -z "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    _script=$(realpath "${BASH_SOURCE[0]}")
    _cmd="bash $(printf '%q' "$_script")"
    [[ $# -gt 0 ]] && _cmd+=" $(printf '%q ' "$@")"
    if tmux has-session -t main 2>/dev/null; then
        tmux new-window -d -t main: -n "install-packages" "$_cmd"
        echo "▶️  Launched in tmux session 'main' (new window). Attach: tmux attach -t main"
    else
        tmux new-session -d -s genesis -n "install-packages" "$_cmd"
        echo "▶️  Launched in tmux session 'genesis'. Attach: tmux attach -t genesis"
    fi
    exit 0
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Core packages installed on all systems.
APT_PACKAGES=(
    curl wget git mc task-spooler tmux git-delta
    fish fd-find bat neovim gh jq unzip
    ripgrep silversearcher-ag sysstat
)

# Additional packages installed only on systems with a GUI (X11 / Wayland).
APT_GUI_PACKAGES=(
    phinger-cursor-theme fonts-ubuntu-classic xclip colorized-logs
)

# Go packages installed with `go install`.
GO_PACKAGES=(
    github.com/charmbracelet/gum@latest
    github.com/jesseduffield/lazydocker@latest
    github.com/jesseduffield/lazygit@latest
    github.com/muesli/duf@latest
    https://github.com/antonmedv/fx@latest
)

# Python tools installed with `uv tool install` after uv is available.
UV_TOOLS=(
    tldr
)

# Cargo (Rust) packages installed with `cargo install`.
CARGO_PACKAGES=(
    reef-shell
    du-dust
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
    [[ "${INSTALL_FORCE:-0}" == 1 || "${UPDATE_ONLY:-0}" == 1 ]] && return 0
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

purge_neofetch() {
    if _apt_pkg_is_installed neofetch; then
        echo "🗑️  Removing neofetch (deprecated)..."
        _run_apt purge -y -qq neofetch
        echo "✅ neofetch purged"
    else
        echo "✅ neofetch (already removed)"
    fi
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

install_fastfetch() {
    if ! _want_install_cmd fastfetch; then
        echo "✅ Fastfetch"
        return 0
    fi

    local REPO="fastfetch-cli/fastfetch"
    local m os ver deb_arch
    m="$(uname -m)"
    os="$(uname -s)"

    case "$m" in
        x86_64|amd64) deb_arch=amd64 ;;
        aarch64|arm64) deb_arch=aarch64 ;;
        i686|i386)     deb_arch=i686 ;;
        *)
            echo "❌ No fastfetch binary for architecture ${m}" >&2
            return 1
            ;;
    esac

    local auth=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    elif [[ -n "${GH_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ${GH_TOKEN}")
    fi

    local release_json
    release_json=$(curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: run_onchange-install-packages" \
        "${auth[@]}" \
        "https://api.github.com/repos/${REPO}/releases/latest")

    ver=$(printf '%s' "$release_json" | jq -r '.tag_name')
    if [[ -z "$ver" || "$ver" == "null" ]]; then
        echo "❌ Failed to resolve fastfetch release (GitHub API)." >&2
        return 1
    fi

    echo "🌐 Installing fastfetch ${ver} from GitHub..."

    local deb_file deb_url deb_path
    if [[ "$os" == Linux ]] && command -v apt-get >/dev/null 2>&1 && [[ -f /etc/debian_version ]]; then
        # Prefer -polyfilled variant (works on older glibc like RasPi OS / Debian 11)
        # Falls back to regular if polyfilled isn't available for this arch.
        deb_file="fastfetch-linux-${deb_arch}-polyfilled.deb"
        deb_url=$(printf '%s' "$release_json" | jq -r --arg name "$deb_file" \
            '.assets[] | select(.name == $name) | .browser_download_url' | head -n1)
        if [[ -z "$deb_url" ]]; then
            deb_file="fastfetch-linux-${deb_arch}.deb"
            deb_url=$(printf '%s' "$release_json" | jq -r --arg name "$deb_file" \
                '.assets[] | select(.name == $name) | .browser_download_url' | head -n1)
        fi

        if [[ -z "$deb_url" ]]; then
            echo "⚠️  No .deb release asset named ${deb_file}, falling back to tarball..." >&2
        else
            deb_path=$(mktemp /tmp/fastfetch-XXXXXX.deb)
            echo "⬇️  Downloading ${deb_file}..."
            if curl -fsSL -o "$deb_path" "$deb_url"; then
                if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
                    -qq -o Dpkg::Use-Pty=0 "$deb_path"; then
                    rm -f "$deb_path"
                    echo "✅ fastfetch ${ver} installed"
                    return 0
                fi
                rm -f "$deb_path"
                echo "⚠️  .deb install failed, falling back to tarball..." >&2
            else
                rm -f "$deb_path"
                echo "⚠️  Download failed for ${deb_file}, falling back to tarball..." >&2
            fi
        fi
    fi

    # Fallback: tarball install (non-Debian systems or .deb path failed)
    local tar_file tar_url tmpdir
    # Prefer -polyfilled variant for old glibc compatibility, fall back to regular
    tar_file="fastfetch-linux-${deb_arch}-polyfilled.tar.gz"
    tar_url=$(printf '%s' "$release_json" | jq -r --arg name "$tar_file" \
        '.assets[] | select(.name == $name) | .browser_download_url' | head -n1)
    if [[ -z "$tar_url" ]]; then
        tar_file="fastfetch-linux-${deb_arch}.tar.gz"
        tar_url=$(printf '%s' "$release_json" | jq -r --arg name "$tar_file" \
            '.assets[] | select(.name == $name) | .browser_download_url' | head -n1)
    fi

    if [[ -z "$tar_url" ]]; then
        echo "❌ No release asset named ${tar_file} either" >&2
        return 1
    fi

    tmpdir=$(mktemp -d)
    echo "⬇️  Downloading ${tar_file}..."
    curl -fsSL -o "${tmpdir}/${tar_file}" "$tar_url" || { rm -rf "$tmpdir"; return 1; }
    tar -xzf "${tmpdir}/${tar_file}" -C "$tmpdir"
    local extract_dir="${tar_file%.tar.gz}"
    sudo install -m 0755 "${tmpdir}/${extract_dir}/usr/bin/fastfetch" "/usr/local/bin/fastfetch"
    sudo install -m 0755 "${tmpdir}/${extract_dir}/usr/bin/flashfetch" "/usr/local/bin/flashfetch" 2>/dev/null || true
    rm -rf "$tmpdir"
    echo "✅ fastfetch ${ver} installed (tarball)"
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
    # In update mode, skip apt-repo-based installs — apt upgrade handles them.
    if [[ "${UPDATE_ONLY:-0}" == 1 ]]; then
        echo "✅ Eza (apt upgrade handles updates)"
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

# NOT IN USE: superseded by install_helix_from_source below which compiles the
# latest Helix from source using Cargo instead of downloading a pre-built release.
# install_helix() {
#     if ! _want_install_cmd hx; then
#         echo "✅ helix"
#         return 0
#     fi
#
#     local REPO="helix-editor/helix"
#     local m os release_json ver
#     m="$(uname -m)"
#     os="$(uname -s)"
#
#     local auth=()
#     if [[ -n "${GITHUB_TOKEN:-}" ]]; then
#         auth=(-H "Authorization: Bearer ***")
#     elif [[ -n "${GH_TOKEN:-}" ]]; then
#         auth=(-H "Authorization: Bearer ***")
#     fi
#
#     release_json=$(curl -fsSL \
#         -H "Accept: application/vnd.github+json" \
#         -H "User-Agent: run_onchange-install-packages" \
#         "${auth[@]}" \
#         "https://api.github.com/repos/${REPO}/releases/latest")
#
#     ver=$(printf '%s' "$release_json" | jq -r '.tag_name')
#     if [[ -z "$ver" || "$ver" == "null" ]]; then
#         echo "❌ Failed to resolve helix release (GitHub API)." >&2
#         return 1
#     fi
#
#     echo "🌐 Installing helix ${ver}..."
#
#     # On x86_64 Debian/Ubuntu, prefer the official .deb package from GitHub.
#     if [[ "$os" == Linux ]] && command -v apt-get >/dev/null 2>&1 \
#        && [[ -f /etc/debian_version ]] && [[ "$m" == "x86_64" ]]; then
#         local deb_file deb_url deb_path
#         deb_file=$(printf '%s' "$release_json" | jq -r \
#             '.assets[] | select(.name | endswith("_amd64.deb")) | .name' | head -n1)
#         deb_url=$(printf '%s' "$release_json" | jq -r \
#             '.assets[] | select(.name | endswith("_amd64.deb")) | .browser_download_url' | head -n1)
#         if [[ -n "$deb_file" && -n "$deb_url" ]]; then
#             deb_path=$(mktemp /tmp/helix-XXXXXX.deb)
#             echo "⬇️  Downloading ${deb_file}..."
#             if curl -fsSL -o "$deb_path" "$deb_url" \
#                && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
#                   -qq -o Dpkg::Use-Pty=0 "$deb_path"; then
#                 rm -f "$deb_path"
#                 echo "✅ helix ${ver} installed"
#                 return 0
#             fi
#             rm -f "$deb_path"
#             echo "⚠️  .deb install failed, falling back to tarball..." >&2
#         fi
#     fi
#
#     # Tarball install — covers aarch64 (Raspberry Pi 4/5 with 64-bit OS) and x86_64 fallback.
#     local asset_suffix
#     case "${os}-${m}" in
#         Linux-x86_64|Linux-amd64)
#             asset_suffix="x86_64-linux.tar.xz" ;;
#         Linux-aarch64|Linux-arm64)
#             asset_suffix="aarch64-linux.tar.xz" ;;
#         *)
#             echo "❌ Unsupported OS/arch for helix: ${os} (${m})" >&2
#             return 1
#             ;;
#     esac
#
#     local asset_name="helix-${ver}-${asset_suffix}"
#     local asset_url
#     asset_url=$(printf '%s' "$release_json" | jq -r --arg name "$asset_name" \
#         '.assets[] | select(.name == $name) | .browser_download_url' | head -n1)
#     if [[ -z "$asset_url" ]]; then
#         echo "❌ No release asset named ${asset_name}" >&2
#         return 1
#     fi
#
#     # Install to /usr/local/lib/helix/ so the binary finds its runtime directory
#     # alongside it (helix resolves runtime relative to its own real path).
#     local install_dir="/usr/local/lib/helix"
#     local tmpdir
#     tmpdir=$(mktemp -d)
#
#     echo "⬇️  Downloading ${asset_name}..."
#     if ! curl --progress-bar -L -o "${tmpdir}/${asset_name}" "$asset_url"; then
#         rm -rf "$tmpdir"
#         return 1
#     fi
#     tar -xJf "${tmpdir}/${asset_name}" -C "$tmpdir"
#
#     local extracted_dir="${tmpdir}/helix-${ver}-${asset_suffix%.tar.xz}"
#     sudo rm -rf "$install_dir"
#     sudo mv "$extracted_dir" "$install_dir"
#     sudo chmod +x "${install_dir}/hx"
#     sudo ln -sf "${install_dir}/hx" /usr/local/bin/hx
#
#     rm -rf "$tmpdir"
#     echo "✅ helix ${ver} installed (runtime: ${install_dir}/runtime)"
# }

# Compile the latest Helix editor from source using Cargo.
# Requires Rust/cargo to be installed before this function is called.
# Source is cloned/updated at ~/projects/helix; the hx binary is placed in
# ~/.cargo/bin/ by `cargo install` and the runtime directory is symlinked
# into ~/.config/helix/runtime so Helix finds grammars and themes.
install_helix_from_source() {
    # Skip if hx is already present, unless it's the old pre-built release (25.07.1)
    # which should be migrated to the compiled-from-source version.
    if command -v hx >/dev/null 2>&1; then
        local current_ver
        current_ver=$(hx -V 2>/dev/null | awk '{print $2}')
        if [[ "$current_ver" != "25.07.1" ]] && [[ "${INSTALL_FORCE:-0}" != 1 ]] && [[ "${UPDATE_ONLY:-0}" != 1 ]]; then
            echo "✅ helix"
            return 0
        fi
    fi

    local cargo_cmd
    cargo_cmd=$(command -v cargo 2>/dev/null || true)
    [[ -z "$cargo_cmd" ]] && [[ -x "${HOME}/.cargo/bin/cargo" ]] && cargo_cmd="${HOME}/.cargo/bin/cargo"
    if [[ -z "$cargo_cmd" ]]; then
        echo "❌ cargo is not available; cannot build helix from source" >&2
        return 1
    fi

    # Migrate from old pre-built release install: remove /usr/local/lib/helix and
    # the symlink at /usr/local/bin/hx that pointed to it.
    if [[ -d /usr/local/lib/helix ]]; then
        echo "🧹 Removing old pre-built helix installation from /usr/local/lib/helix..."
        sudo rm -rf /usr/local/lib/helix
    fi
    if [[ -L /usr/local/bin/hx ]]; then
        echo "🧹 Removing old /usr/local/bin/hx symlink..."
        sudo rm -f /usr/local/bin/hx
    fi

    local src_dir="${HOME}/projects/helix"

    local commit_before=""
    if [[ -d "${src_dir}/.git" ]]; then
        commit_before=$(git -C "$src_dir" rev-parse HEAD 2>/dev/null || true)
        echo "🔀 Updating helix source at ${src_dir}..."
        git -C "$src_dir" pull --ff-only
    else
        echo "🔀 Cloning helix source into ${src_dir}..."
        mkdir -p "${HOME}/projects"
        git clone https://github.com/helix-editor/helix "$src_dir"
    fi

    local commit_after
    commit_after=$(git -C "$src_dir" rev-parse HEAD 2>/dev/null || true)

    # Skip compilation if the repo has not changed and hx is already installed.
    if [[ -n "$commit_before" ]] && [[ "$commit_before" == "$commit_after" ]] \
        && command -v hx >/dev/null 2>&1 && [[ "${INSTALL_FORCE:-0}" != 1 ]]; then
        local ver
        ver=$(git -C "$src_dir" describe --tags --abbrev=0 2>/dev/null || echo "unknown")
        mkdir -p "${HOME}/.config/helix"
        ln -Tsf "${src_dir}/runtime" "${HOME}/.config/helix/runtime"
        echo "✅ helix ${ver} (no changes in repository, skipping recompile)"
        return 0
    fi

    echo "🦀 Compiling helix (optimized)..."
    (
        cd "$src_dir"
        "$cargo_cmd" install \
            --profile opt \
            --config 'build.rustflags="-C target-cpu=native"' \
            --path helix-term \
            --locked
    )

    # Symlink the runtime directory so Helix finds grammars and themes.
    mkdir -p "${HOME}/.config/helix"
    ln -Tsf "${src_dir}/runtime" "${HOME}/.config/helix/runtime"

    local ver
    ver=$(git -C "$src_dir" describe --tags --abbrev=0 2>/dev/null || echo "unknown")
    echo "✅ helix ${ver} compiled and installed (runtime: ${src_dir}/runtime)"
}

install_scooter() {
    if ! _want_install_cmd scooter; then
        echo "✅ scooter"
        return 0
    fi

    local REPO="thomasschafer/scooter"
    local m os release_json ver

    m="$(uname -m)"
    os="$(uname -s)"

    local auth=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ***")
    elif [[ -n "${GH_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ***")
    fi

    release_json=$(curl -fsSL \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: run_onchange-install-packages" \
        "${auth[@]}" \
        "https://api.github.com/repos/${REPO}/releases/latest")

    ver=$(printf '%s' "$release_json" | jq -r '.tag_name')
    if [[ -z "$ver" || "$ver" == "null" ]]; then
        echo "❌ Failed to resolve scooter release (GitHub API)." >&2
        return 1
    fi

    echo "🌐 Installing scooter ${ver}..."

    local asset_suffix
    case "${os}-${m}" in
        Linux-x86_64|Linux-amd64)
            asset_suffix="x86_64-unknown-linux-musl" ;;
        Linux-aarch64|Linux-arm64)
            asset_suffix="aarch64-unknown-linux-musl" ;;
        *)
            echo "❌ Unsupported OS/arch for scooter: ${os} (${m})" >&2
            return 1 ;;
    esac

    local asset_name="scooter-${ver}-${asset_suffix}.tar.gz"
    local asset_url
    asset_url=$(printf '%s' "$release_json" | jq -r --arg name "$asset_name" \
        '.assets[] | select(.name == $name) | .browser_download_url' | head -n1)

    if [[ -z "$asset_url" ]]; then
        echo "❌ No release asset named ${asset_name}" >&2
        return 1
    fi

    local install_dir="${HOME}/.local/bin"
    mkdir -p "$install_dir"

    local tmpdir
    tmpdir=$(mktemp -d)

    echo "⬇️  Downloading ${asset_name}..."
    if ! curl --progress-bar -L -o "${tmpdir}/${asset_name}" "$asset_url"; then
        rm -rf "$tmpdir"
        return 1
    fi

    tar -xzf "${tmpdir}/${asset_name}" -C "$tmpdir"

    # The tarball contains a single directory: scooter-${ver}-${asset_suffix}/scooter
    local extracted_dir="${tmpdir}/scooter-${ver}-${asset_suffix}"
    if [[ -d "$extracted_dir" ]] && [[ -f "${extracted_dir}/scooter" ]]; then
        mv "${extracted_dir}/scooter" "${install_dir}/scooter"
    elif [[ -f "${tmpdir}/scooter" ]]; then
        # Some tarballs extract flat (no containing directory)
        mv "${tmpdir}/scooter" "${install_dir}/scooter"
    else
        echo "❌ Could not find scooter binary in extracted archive" >&2
        ls -la "${tmpdir}" >&2
        rm -rf "$tmpdir"
        return 1
    fi

    chmod +x "${install_dir}/scooter"
    rm -rf "$tmpdir"
    echo "✅ scooter ${ver} installed"
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

install_rust() {
    local cargo_cmd
    cargo_cmd=$(command -v cargo 2>/dev/null || true)
    [[ -z "$cargo_cmd" ]] && [[ -x "${HOME}/.cargo/bin/cargo" ]] && cargo_cmd="${HOME}/.cargo/bin/cargo"

    if [[ -n "$cargo_cmd" ]] && [[ "${INSTALL_FORCE:-0}" != 1 ]]; then
        echo "✅ Rust ($("$cargo_cmd" --version 2>/dev/null | awk '{print $2}'))"
        return 0
    fi
    echo "🌐 Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    echo "✅ Rust installed"
}

install_cargo_packages() {
    local cargo_cmd
    cargo_cmd=$(command -v cargo 2>/dev/null || true)
    [[ -z "$cargo_cmd" ]] && [[ -x "${HOME}/.cargo/bin/cargo" ]] && cargo_cmd="${HOME}/.cargo/bin/cargo"
    if [[ -z "$cargo_cmd" ]]; then
        echo "❌ cargo is not available, cannot install cargo packages" >&2
        return 1
    fi

    local package command_name failed_packages=()
    for package in "${CARGO_PACKAGES[@]}"; do
        command_name="${package}"
        if [[ "${INSTALL_FORCE:-0}" != 1 ]] && [[ "${UPDATE_ONLY:-0}" != 1 ]] \
           && command -v "$command_name" >/dev/null 2>&1; then
            echo "✅ ${command_name}"
            continue
        fi

        echo "🦀 Installing ${package}..."
        if "$cargo_cmd" install "$package"; then
            echo "✅ Installed ${package}"
        else
            echo "❌ Failed to install ${package}" >&2
            failed_packages+=("$package")
        fi
    done

    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo "⚠️  Cargo packages that failed to install: ${failed_packages[*]}" >&2
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
    # In update mode, skip apt-repo-based installs — apt upgrade handles them.
    if [[ "${UPDATE_ONLY:-0}" == 1 ]]; then
        echo "✅ task (apt upgrade handles updates)"
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
    UPDATE_ONLY=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                INSTALL_FORCE=1
                shift
                ;;
            --update)
                UPDATE_ONLY=1
                shift
                ;;
            -h|--help)
                echo "Usage: ${0##*/} [--force] [--update] [--help]"
                echo "  --force   Re-run all installers (including apt)"
                echo "  --update  Re-run non-apt installers only (for periodic updates)"
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                echo "Usage: ${0##*/} [--force] [--update] [--help]" >&2
                exit 1
                ;;
        esac
    done
    export INSTALL_FORCE
    export UPDATE_ONLY

    if [[ "$UPDATE_ONLY" == 0 ]]; then
        install_apt_packages
        purge_neofetch
        ensure_fd_symlink
    fi
    install_uv
    install_uv_tools
    install_fzf
    install_starship
    install_eza
    install_fastfetch
    install_tv
    install_scooter
    install_amoxide
    install_go
    install_go_packages
    install_rust
    install_cargo_packages
    install_helix_from_source
    install_task
    install_firacode_nerd_font_if_gui
    install_jetbrains_mono_font_if_gui
    # install_zellij -- probably sticking with tmux
    change_shell_to_fish
}

main "$@"
_exit_code=$?

if [[ -n "${TMUX:-}" ]] && command -v fish >/dev/null 2>&1; then
    fish -c 'toast "Chezmoi install packages completed"' 2>/dev/null || true
fi

exit $_exit_code
