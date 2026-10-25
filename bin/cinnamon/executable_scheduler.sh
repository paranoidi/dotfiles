#!/usr/bin/env bash
# Build sched_ext schedulers from source and run one as a systemd service.
# lavd (default) favours interactive tasks (X, compositor, input) under CPU
# contention; bpfland is available for runtime switching (e.g. Bitwig).
# If a scheduler misbehaves the kernel ejects it and falls back to the default.
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────
SCX_VERSION="${SCX_VERSION:-v1.1.4}"   # release tag; bump and re-run install to upgrade
SCHEDS=(scx_lavd scx_bpfland)          # built and installed; first one is the default
DEFAULT=${SCHEDS[0]}
# clang 18 (noble's default) miscompiles arena memory; lavd's verifier load fails
# with "invalid mem access 'scalar'" in sdt_alloc. scx wants >=22 for arena code.
CLANG=clang-20
SRC_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/scx"
BIN_DIR=/usr/local/bin
STAMP=/usr/local/share/scx/version
SERVICE=scx.service
SERVICE_FILE=/etc/systemd/system/$SERVICE
SWITCH=/usr/local/sbin/scx-switch
SUDOERS=/etc/sudoers.d/scx-switch
DEPS=(build-essential "$CLANG" "llvm-${CLANG#clang-}" pkg-config libelf-dev libzstd-dev zlib1g-dev
      libbpf-dev libseccomp-dev protobuf-compiler)

usage() {
  cat <<EOF
Usage: $(basename "$0") <install|uninstall|-h>

  install     Build ${SCHEDS[*]} ($SCX_VERSION), enable $DEFAULT as $SERVICE
              and install $SWITCH. Idempotent: skips steps already done.
              SCX_VERSION=vX.Y.Z overrides the tag.
  uninstall   Stop and remove the service, binaries and switch helper. Leaves
              apt packages and the source checkout ($SRC_DIR).
  -h, --help  Show this help.

Runtime switch (passwordless, reverts at reboot):
  sudo $SWITCH <$(IFS='|'; echo "${SCHEDS[*]}")|default>

Status:  systemctl status $SERVICE
Active:  cat /sys/kernel/sched_ext/state /sys/kernel/sched_ext/root/ops
EOF
}

install_scx() {
  [[ $(cat /sys/kernel/sched_ext/state 2>/dev/null) ]] || {
    echo "❌ Kernel has no sched_ext (CONFIG_SCHED_CLASS_EXT)." >&2; exit 1; }
  command -v cargo >/dev/null || { echo "❌ cargo not found (install rustup)." >&2; exit 1; }

  local missing=() d s
  for d in "${DEPS[@]}"; do dpkg -s "$d" &>/dev/null || missing+=("$d"); done
  if (( ${#missing[@]} )); then
    echo "📦 Installing: ${missing[*]}"
    sudo apt update || true
    sudo apt install -y "${missing[@]}"
  else
    echo "📦 Build dependencies present, skipping."
  fi

  # Stamp holds version, compiler and scheduler list; changing any forces a rebuild.
  local want="$SCX_VERSION $CLANG ${SCHEDS[*]}" have_all=1
  for s in "${SCHEDS[@]}"; do [[ -x $BIN_DIR/$s ]] || have_all=0; done
  if (( have_all )) && [[ $(cat "$STAMP" 2>/dev/null) == "$want" ]]; then
    echo "🔧 ${SCHEDS[*]} $SCX_VERSION already installed, skipping build."
  else
    if [[ -d $SRC_DIR/.git ]]; then
      git -C "$SRC_DIR" fetch --tags --quiet
    else
      git clone --quiet https://github.com/sched-ext/scx.git "$SRC_DIR"
    fi
    git -C "$SRC_DIR" -c advice.detachedHead=false checkout --quiet "$SCX_VERSION"

    echo "🔨 Building ${SCHEDS[*]} $SCX_VERSION (takes a few minutes)..."
    # Minimal PATH: ~/bin/install is a directory, and make's exec of it fails
    # with EACCES instead of falling through to /usr/bin/install.
    local cargo_dir
    cargo_dir=$(dirname "$(command -v cargo)")
    (cd "$SRC_DIR" && PATH="$cargo_dir:/usr/local/bin:/usr/bin:/bin" BPF_CLANG="$CLANG" \
      cargo build --release "${SCHEDS[@]/#/--package=}")

    # Stop first: the running binary can't be overwritten in place.
    sudo systemctl stop "$SERVICE" 2>/dev/null || true
    for s in "${SCHEDS[@]}"; do
      sudo install -D -m 755 "$SRC_DIR/target/release/$s" "$BIN_DIR/$s"
      echo "  ✓ $BIN_DIR/$s"
    done
    echo "$want" | sudo install -D -m 644 /dev/stdin "$STAMP"
  fi

  sudo tee "$SERVICE_FILE" >/dev/null <<UNIT
[Unit]
Description=sched_ext scheduler
Documentation=https://github.com/sched-ext/scx
# Repeated ejections by the kernel watchdog mean it's not working here; give up.
StartLimitIntervalSec=300
StartLimitBurst=3

[Service]
Type=simple
ExecStart=$BIN_DIR/$DEFAULT
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

  # Root-owned helper so the allowlist can't be edited by the user it serves.
  # The override lives in /run, so a crashed caller is undone by a reboot.
  sudo tee "$SWITCH" >/dev/null <<HELPER
#!/bin/bash
# Switch scx.service to another scheduler until reboot. Installed by scheduler.sh.
set -euo pipefail
DROPIN=/run/systemd/system/$SERVICE.d/switch.conf
case "\${1:-}" in
  default) rm -f "\$DROPIN" ;;
  $(IFS='|'; echo "${SCHEDS[*]}"))
    mkdir -p "\$(dirname "\$DROPIN")"
    printf '[Service]\nExecStart=\nExecStart=$BIN_DIR/%s\n' "\$1" > "\$DROPIN" ;;
  *) echo "Usage: \$0 <$(IFS='|'; echo "${SCHEDS[*]}")|default>" >&2; exit 1 ;;
esac
systemctl daemon-reload
systemctl reset-failed $SERVICE 2>/dev/null || true
systemctl restart $SERVICE
HELPER
  sudo chmod 755 "$SWITCH"

  local rule="$USER ALL=(root) NOPASSWD: $SWITCH"
  echo "$rule" | sudo tee "$SUDOERS.tmp" >/dev/null
  sudo chmod 440 "$SUDOERS.tmp"
  sudo visudo -cqf "$SUDOERS.tmp" && sudo mv "$SUDOERS.tmp" "$SUDOERS"
  echo "  ✓ $SWITCH (passwordless via $SUDOERS)"

  sudo systemctl daemon-reload
  sudo systemctl enable "$SERVICE" --quiet
  # Clear the start limit left by earlier failures, or restart is refused.
  sudo systemctl reset-failed "$SERVICE" 2>/dev/null || true
  sudo systemctl restart "$SERVICE"

  # Loading + verifying the BPF program takes a few seconds.
  local state ops i
  for i in {1..15}; do
    state=$(cat /sys/kernel/sched_ext/state)
    [[ $state == enabled ]] && break
    systemctl is-failed --quiet "$SERVICE" && break
    sleep 1
  done
  ops=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || true)
  if [[ $state == enabled ]]; then
    echo "✅ sched_ext $state, scheduler: ${ops:-?}"
  else
    echo "❌ sched_ext is $state. Logs:" >&2
    journalctl -u "$SERVICE" -n 20 --no-pager >&2
    exit 1
  fi
}

uninstall_scx() {
  if [[ -f $SERVICE_FILE ]]; then
    sudo systemctl disable --now "$SERVICE" --quiet || true
    sudo rm -f "$SERVICE_FILE"
    sudo rm -rf "/run/systemd/system/$SERVICE.d"
    sudo systemctl daemon-reload
    echo "  ✓ removed $SERVICE"
  fi
  sudo rm -f "$SUDOERS" "$SWITCH" "$STAMP" "${SCHEDS[@]/#/$BIN_DIR/}"
  sudo rmdir --ignore-fail-on-non-empty "$(dirname "$STAMP")" 2>/dev/null || true
  echo "✅ Uninstalled. sched_ext: $(cat /sys/kernel/sched_ext/state) (default scheduler)"
}

# cargo/rustup live in the user's home; per-command sudo does the root parts.
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  echo "Run as your user, not root (it uses your rustup toolchain and sudo as needed)." >&2
  exit 1
fi

case "${1:-}" in
  install)    install_scx ;;
  uninstall)  uninstall_scx ;;
  -h|--help)  usage ;;
  *)          usage >&2; exit 1 ;;
esac
