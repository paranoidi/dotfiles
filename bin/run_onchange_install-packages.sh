#!/usr/bin/env bash
set -euo pipefail

# If not already inside tmux but tmux is available, relaunch inside a tmux
# window so the terminal is freed for the duration of the (potentially long)
# installation.  Prefer an existing "main" session; fall back to a new session
# named "genesis".
# --list/--help just print and exit; don't bury their output in a detached tmux window.
_no_tmux=0
for _arg in "$@"; do
    case "$_arg" in
        -l|--list|-h|--help) _no_tmux=1 ;;
    esac
done
if [[ "$_no_tmux" == 0 ]] && [[ -z "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then
    _script=$(realpath "${BASH_SOURCE[0]}")
    # chezmoi (which runs this as run_onchange_install-packages.sh) executes it
    # from a temp file it deletes as soon as this process exits. Since we exit
    # right after handing off to a detached tmux job, that job would try to
    # `bash` a file chezmoi already removed. Copy it somewhere stable first.
    _script_copy=$(mktemp /tmp/install-packages-XXXXXX.sh)
    cp "$_script" "$_script_copy"
    _cmd="bash $(printf '%q' "$_script_copy")"
    [[ $# -gt 0 ]] && _cmd+=" $(printf '%q ' "$@")"
    _cmd+="; rm -f $(printf '%q' "$_script_copy")"
    # Keep the pane open (dropped into an interactive shell) after the install
    # finishes so results stay visible instead of the window closing.
    _cmd+="; exec bash"
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

# System packages that belong in apt (shell, libs, desktop glue).
APT_PACKAGES=(
    curl wget git mc task-spooler tmux
    fish unzip
    silversearcher-ag sysstat
    build-essential
)

# Additional packages installed only on systems with a GUI (X11 / Wayland).
APT_GUI_PACKAGES=(
    phinger-cursor-theme fonts-ubuntu-classic xclip colorized-logs
)

# Tools live in ~/.config/mise/mise.toml (chezmoi-managed). Formerly: custom
# GitHub/.deb installers, go install, cargo install, apt CLIs, and an inline
# MISE_TOOLS list that `mise use -g` wrote into config.toml.

# Python tools installed with `uv tool install` after uv (via mise) is available.
UV_TOOLS=(
    tldr
    pyright
)

# Non-mise installers: <name>:<function>. Mise tools come from mise.toml.
# helix stays source-built (native opt profile) — prebuilt aqua/mise hx is not equivalent.
# purge-pre-mise runs after mise so replacements exist before apt/old bins are removed.
INSTALLERS=(
    "apt:install_apt_group"
    "mise:install_mise_tools"
    "fzf-tmux:install_fzf_tmux"
    "purge-pre-mise:purge_pre_mise_duplicates"
    "uv-tools:install_uv_tools"
    "helix:install_helix_from_source"
    "fira-font:install_firacode_nerd_font_if_gui"
    "jetbrains-font:install_jetbrains_mono_font_if_gui"
    "fish:change_shell_to_fish"
)

MISE_CONFIG="${HOME}/.config/mise/mise.toml"

_installer_for() {
    local entry
    for entry in "${INSTALLERS[@]}"; do
        if [[ "${entry%%:*}" == "$1" ]]; then
            printf '%s\n' "${entry#*:}"
            return 0
        fi
    done
    return 1
}

# =============================================================================

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

_apt_out_filter() {
    grep -v -E 'already the newest version|upgraded,|newly installed|to remove|not upgraded|WARNING: apt does not have a stable CLI interface|^Hit:|^Get:|^Ign:|Reading package lists|Building dependency tree|Reading state information|^Fetched |list --upgradable.*see them' | awk 'NF'
}

_run_apt() {
    sudo apt "$@" 2>&1 | _apt_out_filter
    return "${PIPESTATUS[0]}"
}

_apt_pkg_is_available() {
    apt-cache show "$1" >/dev/null 2>&1
}

_apt_pkg_is_installed() {
    local pkg=$1 st
    st=$(dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null) || return 1
    [[ "$st" == "installed" ]]
}

_want_install_apt_pkg() {
    [[ "${INSTALL_FORCE:-0}" == 1 ]] && return 0
    # Skip if the dpkg is present, or if a same-named binary already exists
    # (e.g. source-built tmux) — package name usually matches the command.
    ! _apt_pkg_is_installed "$1" && ! command -v "$1" >/dev/null 2>&1
}

_want_install_cmd() {
    [[ "${INSTALL_FORCE:-0}" == 1 || "${UPDATE_ONLY:-0}" == 1 ]] && return 0
    ! command -v "$1" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# mise
# -----------------------------------------------------------------------------

ensure_mise() {
    export PATH="${HOME}/.local/bin:${PATH}"
    if ! command -v mise >/dev/null 2>&1; then
        echo "🌐 Installing mise..."
        curl -fsSL https://mise.run | sh
        export PATH="${HOME}/.local/bin:${PATH}"
    fi
    if ! command -v mise >/dev/null 2>&1; then
        echo "❌ mise not found on PATH after install (expected ${HOME}/.local/bin/mise)" >&2
        return 1
    fi
    # Activate for this process so later steps (uv tools, fish check) see mise bins.
    eval "$(mise activate bash)"
    _ensure_mise_fish_hook
}

# conf.d is alphabetical: mise must load before fzf plugins / 90-integrations,
# otherwise those see no fzf/starship after we purge the old ~/.fzf and
# ~/.local/bin copies.
_ensure_mise_fish_hook() {
    local hook="${HOME}/.config/fish/conf.d/00-mise.env.fish"
    local legacy="${HOME}/.config/fish/conf.d/mise.env.fish"
    mkdir -p "$(dirname "$hook")"
    rm -f "$legacy"
    if [[ -f "$hook" ]] && grep -q 'mise activate fish' "$hook"; then
        return 0
    fi
    cat >"$hook" <<'EOF'
# Managed by run_onchange_install-packages.sh — mise-managed tools on PATH.
# Filename 00- so this runs before fzf/starship conf.d hooks.
if test -x "$HOME/.local/bin/mise"
    $HOME/.local/bin/mise activate fish | source
end
EOF
    echo "✅ wrote ${hook}"
}

# Install tools from chezmoi-managed ~/.config/mise/mise.toml (+ mise.lock).
# cargo.binstall is disabled in that file so cargo:* crates compile quietly.
_mise_out_filter() {
    # Match script ✅/📦 style for mise's plain status lines.
    sed -E \
        -e 's/^mise all tools are installed$/✅ mise/' \
        -e 's/^mise All tools are up to date$/✅ mise/'
}

_mise_run() {
    mise "$@" 2>&1 | _mise_out_filter
    return "${PIPESTATUS[0]}"
}

_mise_install() {
    local flags=(-y) t
    [[ "${INSTALL_FORCE:-0}" == 1 ]] && flags+=(-f)
    if [[ $# -eq 0 ]]; then
        if [[ "${UPDATE_ONLY:-0}" == 1 ]]; then
            echo "📦 mise upgrade"
            _mise_run upgrade "${flags[@]}"
        else
            echo "📦 mise install"
            _mise_run install "${flags[@]}"
        fi
        return
    fi
    echo "📦 mise install $*"
    local specs=()
    for t in "$@"; do
        specs+=("$t")
    done
    _mise_run install "${flags[@]}" "${specs[@]}"
}

install_mise_tools() {
    ensure_mise
    if [[ ! -f "${MISE_CONFIG}" ]]; then
        echo "❌ missing ${MISE_CONFIG} (chezmoi-managed mise config)" >&2
        return 1
    fi
    mise trust "${MISE_CONFIG}" >/dev/null 2>&1 || true
    _mise_install
}

# -----------------------------------------------------------------------------
# fzf-tmux (companion script, not shipped by mise's binary-only fzf install)
# -----------------------------------------------------------------------------

# mise's aqua-backed fzf install is just the compiled binary; fzf-tmux is a
# plain shell script from the fzf git repo (bin/fzf-tmux), normally shipped by
# distro packages built from source. Fetch it pinned to the mise-installed fzf
# version so the two stay in sync.
install_fzf_tmux() {
    local dest="${HOME}/bin/fzf-tmux"
    if [[ -x "$dest" ]] && [[ "${INSTALL_FORCE:-0}" != 1 ]]; then
        echo "✅ fzf-tmux"
        return 0
    fi
    local ver tag
    ver=$(grep -oP '^fzf\s*=\s*"\K[^"]+' "$MISE_CONFIG" 2>/dev/null)
    tag="${ver:+v$ver}"
    tag="${tag:-master}"
    echo "🌐 Installing fzf-tmux (${tag})..."
    mkdir -p "${HOME}/bin"
    curl -fsSL -o "$dest" "https://raw.githubusercontent.com/junegunn/fzf/${tag}/bin/fzf-tmux"
    chmod +x "$dest"
    echo "✅ fzf-tmux installed"
}

# Remove pre-mise copies of tools now managed by mise (same apply, after mise).
# Covers apt packages from the old APT_PACKAGES list, GitHub/.deb drop-ins under
# /usr/local and ~/.local, go install bins, cargo install bins for migrated
# crates, the eza apt repo, and the old ~/.fzf / ~/.local/go trees. Idempotent.
# Does not touch rustup/hx (helix stays cargo-built) or unrelated ~/go/bin tools.
purge_pre_mise_duplicates() {
    local apt_pkgs=(
        ripgrep fd-find bat neovim gh jq git-delta
        eza fastfetch television
    )
    local pkg to_purge=()
    for pkg in "${apt_pkgs[@]}"; do
        if _apt_pkg_is_installed "$pkg"; then
            to_purge+=("$pkg")
        fi
    done
    if [[ ${#to_purge[@]} -gt 0 ]]; then
        echo "💀 Purging pre-mise apt packages: ${to_purge[*]}"
        _run_apt purge -y -qq "${to_purge[@]}"
    fi

    # eza was installed via a third-party apt repo; drop the leftover source.
    if [[ -f /etc/apt/sources.list.d/gierens.list ]] || [[ -f /etc/apt/keyrings/gierens.gpg ]]; then
        echo "💀 Removing eza (gierens) apt repo"
        sudo rm -f /etc/apt/sources.list.d/gierens.list /etc/apt/keyrings/gierens.gpg
    fi

    local f
    for f in \
        /usr/local/bin/fd \
        /usr/local/bin/fx \
        /usr/local/bin/starship \
        /usr/local/bin/fastfetch \
        /usr/local/bin/flashfetch \
        "${HOME}/.local/bin/bat" \
        "${HOME}/.local/bin/go" \
        "${HOME}/.local/bin/gofmt" \
        "${HOME}/.local/bin/starship" \
        "${HOME}/.local/bin/scooter" \
        "${HOME}/.local/bin/lazydocker" \
        "${HOME}/.local/bin/uv" \
        "${HOME}/.local/bin/gum" \
        "${HOME}/.local/bin/lazygit" \
        "${HOME}/.local/bin/duf" \
        "${HOME}/.local/bin/fx" \
        "${HOME}/.local/bin/task" \
        "${HOME}/go/bin/gum" \
        "${HOME}/go/bin/lazygit" \
        "${HOME}/go/bin/duf" \
        "${HOME}/go/bin/fx" \
        "${HOME}/go/bin/task" \
        "${HOME}/go/bin/lazydocker" \
        "${HOME}/.cargo/bin/dust" \
        "${HOME}/.cargo/bin/reef" \
        "${HOME}/.cargo/bin/am"
    do
        if [[ -e "$f" || -L "$f" ]]; then
            echo "🗑️  Removing ${f}"
            # /usr/local may need sudo; home paths do not.
            if [[ "$f" == /usr/local/* ]]; then
                sudo rm -f "$f"
            else
                rm -f "$f"
            fi
        fi
    done

    if [[ -d "${HOME}/.fzf" ]]; then
        echo "🗑️  Removing ${HOME}/.fzf (pre-mise fzf)"
        rm -rf "${HOME}/.fzf"
    fi
    if [[ -d "${HOME}/.local/go" ]]; then
        echo "🗑️  Removing ${HOME}/.local/go (pre-mise go tarball)"
        rm -rf "${HOME}/.local/go"
    fi

    # paras-commander (pc): actively developed, updated via maintenance_pc.fish's
    # `go install ... GOPROXY=direct` (rebuilds from a local checkout when present).
    # Never add it to mise.toml. Purge any stray mise-registered tool (e.g. from a
    # manual `mise use -g go:...`) so its shim doesn't shadow the go-installed binary.
    local pc_tools
    pc_tools=$(mise ls -g 2>/dev/null | awk 'tolower($0) ~ /paras-commander/ {print $1}')
    if [[ -n "$pc_tools" ]]; then
        echo "💀 Purging mise-managed pc (paras-commander): ${pc_tools}"
        while IFS= read -r t; do
            # `unuse -g` (not `uninstall -g`, which has no -g flag) both drops
            # the entry from the global config and prunes the install — needed
            # or `mise install` would just reinstall it on the next run.
            [[ -n "$t" ]] && mise unuse -g "$t" 2>&1 | _mise_out_filter
        done <<<"$pc_tools"
    fi

    # `go install` (what maintenance_pc.fish runs) writes to GOBIN, and mise's go
    # plugin points GOBIN at its own toolchain dir — not GOPATH/bin — so a plain
    # `go install .../pc` lands inside mise's install tree even though pc is never
    # a mise-registered tool. `mise ls -g`/`unuse` can't see or remove it; only a
    # direct file check does.
    local pc_bin
    for pc_bin in "${HOME}"/.local/share/mise/installs/go/*/bin/pc; do
        if [[ -e "$pc_bin" || -L "$pc_bin" ]]; then
            echo "💀 Removing ${pc_bin}"
            rm -f "$pc_bin"
        fi
    done

    echo "✅ pre-mise duplicates purged"
}

# -----------------------------------------------------------------------------
# apt
# -----------------------------------------------------------------------------

purge_neofetch() {
    if _apt_pkg_is_installed neofetch; then
        echo "💀 Removing neofetch (deprecated)..."
        _run_apt purge -y -qq neofetch
        echo "✅ neofetch purged"
    fi
}

install_apt_group() {
    [[ "${UPDATE_ONLY:-0}" == 1 ]] && return 0
    install_apt_packages
    purge_neofetch
}

install_apt_packages() {
    local packages_to_install=()
    local packages=("${APT_PACKAGES[@]}")

    if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]] || \
       pgrep -x "Xorg" >/dev/null || \
       pgrep -x "wayland" >/dev/null; then
        packages+=("${APT_GUI_PACKAGES[@]}")
    fi

    if [[ "$IS_RASPI" == 1 ]]; then
        echo "⚠️  Detected Raspberry Pi OS, excluding fish"
        packages=($(printf '%s\n' "${packages[@]}" | grep -v -E '^fish$'))
    fi

    local package
    for package in "${packages[@]}"; do
        if _want_install_apt_pkg "$package"; then
            packages_to_install+=("$package")
        fi
    done

    if [ ${#packages_to_install[@]} -eq 0 ]; then
        echo "✅ All apt packages are already installed"
        return 0
    fi

    echo "📦 Installing packages: ${packages_to_install[*]}"
    local failed_packages=()
    for package in "${packages_to_install[@]}"; do
        if ! _apt_pkg_is_available "$package"; then
            echo "  ⚠️  Skipping $package (not found in apt cache)" >&2
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
    if [ ${#failed_packages[@]} -gt 0 ]; then
        echo "⚠️  Packages that failed to install: ${failed_packages[*]}" >&2
    fi
}

# -----------------------------------------------------------------------------
# uv tools (thin layer on top of mise-provided uv)
# -----------------------------------------------------------------------------

_uv_cmd() {
    if command -v uv >/dev/null 2>&1; then
        command -v uv
        return 0
    fi
    if [[ -x "${HOME}/.local/bin/uv" ]]; then
        printf '%s\n' "${HOME}/.local/bin/uv"
        return 0
    fi
    return 1
}

install_uv_tools() {
    local uv_bin tool failed_tools=()
    uv_bin=$(_uv_cmd || true)
    if [[ -z "$uv_bin" ]]; then
        echo "⚠️  uv not on PATH, skipping uv tool installs" >&2
        return 0
    fi

    for tool in "${UV_TOOLS[@]}"; do
        if ! _want_install_cmd "$tool"; then
            echo "✅ ${tool}"
            continue
        fi
        if [[ "${UPDATE_ONLY:-0}" == 1 ]] && command -v "$tool" >/dev/null 2>&1; then
            echo "📦 Upgrading ${tool} via uv..."
            if "$uv_bin" tool upgrade "$tool" &>/dev/null; then
                echo "✅ ${tool} upgraded"
                continue
            fi
            # ponytail: upgrade can fail if uv doesn't track the tool; fall back to install.
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

# -----------------------------------------------------------------------------
# helix (compiled from source — not the mise/aqua prebuild)
# -----------------------------------------------------------------------------

_cargo_cmd() {
    if command -v cargo >/dev/null 2>&1; then
        command -v cargo
        return 0
    fi
    if [[ -x "${HOME}/.cargo/bin/cargo" ]]; then
        printf '%s\n' "${HOME}/.cargo/bin/cargo"
        return 0
    fi
    return 1
}

# Compile the latest Helix editor from source using Cargo.
# Requires Rust/cargo (via mise) before this runs.
# Source lives at ~/projects/helix; hx goes to ~/.cargo/bin/; runtime is
# symlinked into ~/.config/helix/runtime.
#
# Do not trust `hx -V`'s semver alone: apt helix and a source build at the same
# tag both report e.g. 25.07.1. Match the parenthesized git hash to source HEAD.
install_helix_from_source() {
    local cargo_cmd
    cargo_cmd=$(_cargo_cmd || true)
    if [[ -z "$cargo_cmd" ]]; then
        echo "❌ cargo is not available; cannot build helix from source" >&2
        return 1
    fi

    # Apt/distro helix shadows or confuses PATH; source build owns ~/.cargo/bin/hx.
    if _apt_pkg_is_installed helix; then
        echo "💀 Purging apt helix (using source build instead)"
        _run_apt purge -y -qq helix
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
        git -C "$src_dir" pull --ff-only 2>&1 | grep -v "Already up to date" || true
    else
        echo "🔀 Cloning helix source into ${src_dir}..."
        mkdir -p "${HOME}/projects"
        git clone https://github.com/helix-editor/helix "$src_dir"
    fi

    local commit_after src_short hx_ver hx_hash
    commit_after=$(git -C "$src_dir" rev-parse HEAD 2>/dev/null || true)
    src_short=$(git -C "$src_dir" rev-parse --short=8 HEAD 2>/dev/null || true)

    # hx -V → "helix 25.07.1 (079a789e)" — hash is what distinguishes builds.
    hx_ver=$(hx -V 2>/dev/null || true)
    hx_hash=$(sed -n 's/.*(\([0-9a-f]\{7,\}\)).*/\1/p' <<<"$hx_ver" | head -1)

    # Skip compilation if source unchanged, not forcing, and running hx matches HEAD.
    if [[ -n "$commit_before" ]] && [[ "$commit_before" == "$commit_after" ]] \
        && [[ -n "$hx_hash" ]] && [[ "$commit_after" == "$hx_hash"* ]] \
        && [[ "${INSTALL_FORCE:-0}" != 1 ]]; then
        local ver
        ver=$(git -C "$src_dir" describe --tags --abbrev=0 2>/dev/null || echo "unknown")
        mkdir -p "${HOME}/.config/helix"
        ln -Tsf "${src_dir}/runtime" "${HOME}/.config/helix/runtime"
        echo "✅ helix ${ver} (${src_short}, no changes in repository, skipping recompile)"
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

# -----------------------------------------------------------------------------
# fonts / shell (not mise-shaped)
# -----------------------------------------------------------------------------

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
    local required_version=3.7
    if printf '%s\n%s\n' "$required_version" "$fish_version" | sort -C -V; then
        echo "🏆 Changing shell to fish (version $fish_version)..."
        chsh -s "$fish_path"
    else
        echo "❌ Fish version $fish_version is less than required ${required_version}, skipping shell change" >&2
    fi
}

_list_things() {
    local entry
    for entry in "${INSTALLERS[@]}"; do
        printf '%s\n' "${entry%%:*}"
    done
    export PATH="${HOME}/.local/bin:${PATH}"
    if command -v mise >/dev/null 2>&1; then
        mise ls -g --no-header 2>/dev/null | awk 'NF { print $1 }'
    fi
}

_usage() {
    echo "Usage: ${0##*/} [--force [name...]] [--update] [--list] [--help]"
    echo ""
    echo "  -f, --force [name...]  Re-run installers. With names, force only those things"
    echo "                         (e.g. --force helix fzf cargo:reef-shell). Non-installer"
    echo "                         names are passed to mise install as-is. Bare --force"
    echo "                         re-runs everything."
    echo "  --update               Re-run non-apt installers only (for periodic updates)"
    echo "  -l, --list             List the installable thing names and exit"
}

main() {
    INSTALL_FORCE=0
    UPDATE_ONLY=0
    local FORCE_TARGETS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force)
                INSTALL_FORCE=1
                shift
                while [[ $# -gt 0 && "$1" != -* ]]; do
                    FORCE_TARGETS+=("$1")
                    shift
                done
                ;;
            --update)
                UPDATE_ONLY=1
                shift
                ;;
            -l|--list)
                _list_things
                exit 0
                ;;
            -h|--help)
                _usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                _usage >&2
                exit 1
                ;;
        esac
    done
    export INSTALL_FORCE
    export UPDATE_ONLY

    echo "🛠️ Install packages ..."

    if [[ ${#FORCE_TARGETS[@]} -gt 0 ]]; then
        local name fn
        local mise_targets=()
        for name in "${FORCE_TARGETS[@]}"; do
            if fn=$(_installer_for "$name"); then
                "$fn"
            else
                # Not an installer name — hand to mise (id must match mise.toml / registry).
                mise_targets+=("$name")
            fi
        done
        if [[ ${#mise_targets[@]} -gt 0 ]]; then
            ensure_mise
            _mise_install "${mise_targets[@]}"
        fi
        return
    fi

    local entry
    for entry in "${INSTALLERS[@]}"; do
        "${entry#*:}"
    done
}

main "$@"
_exit_code=$?

if [[ -n "${TMUX:-}" ]] && command -v fish >/dev/null 2>&1; then
    fish -c 'toast "Chezmoi install packages completed"' 2>/dev/null || true
fi

exit $_exit_code
