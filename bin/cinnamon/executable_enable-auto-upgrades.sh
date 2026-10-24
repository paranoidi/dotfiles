#!/usr/bin/env bash
set -euo pipefail

AUTO_UPGRADES_CONF="/etc/apt/apt.conf.d/20auto-upgrades"

 die() {
  echo "error: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    command -v sudo >/dev/null 2>&1 || die "sudo is required when not running as root"
    sudo "$@"
  fi
}

require_apt_unattended_upgrades() {
  command -v apt-get >/dev/null 2>&1 || die "apt-get is required"
  command -v apt-cache >/dev/null 2>&1 || die "apt-cache is required"
  command -v dpkg-query >/dev/null 2>&1 || die "dpkg-query is required"

  apt-cache show unattended-upgrades >/dev/null 2>&1 || die "unattended-upgrades is not available from configured APT sources"
}

install_unattended_upgrades() {
  if dpkg-query -W -f='${Status}' unattended-upgrades 2>/dev/null | grep -q "install ok installed"; then
    info "unattended-upgrades is already installed"
    return
  fi

  info "installing unattended-upgrades"
  as_root apt-get update
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades
}

write_auto_upgrades_config() {
  local desired backup
  desired="$(mktemp)"

  cat >"${desired}" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

  if [[ -f "${AUTO_UPGRADES_CONF}" ]] && cmp -s "${desired}" "${AUTO_UPGRADES_CONF}"; then
    info "${AUTO_UPGRADES_CONF} is already configured"
    rm -f "${desired}"
    return
  fi

  if [[ -f "${AUTO_UPGRADES_CONF}" ]]; then
    backup="${AUTO_UPGRADES_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    info "backing up existing ${AUTO_UPGRADES_CONF} to ${backup}"
    as_root cp --archive "${AUTO_UPGRADES_CONF}" "${backup}"
  fi

  info "configuring ${AUTO_UPGRADES_CONF}"
  as_root install -m 0644 "${desired}" "${AUTO_UPGRADES_CONF}"
  rm -f "${desired}"
}

timer_exists() {
  local timer="$1"

  systemctl list-unit-files --type=timer --no-legend --no-pager "${timer}" 2>/dev/null \
    | awk '{print $1}' \
    | grep -Fxq "${timer}"
}

enable_apt_timers() {
  command -v systemctl >/dev/null 2>&1 || {
    info "systemctl is not available; skipping timer enablement"
    return
  }

  for timer in apt-daily.timer apt-daily-upgrade.timer; do
    if timer_exists "${timer}"; then
      info "ensuring ${timer} is enabled"
      as_root systemctl enable --now "${timer}"
    else
      info "${timer} is not available; skipping"
    fi
  done
}

main() {
  require_apt_unattended_upgrades
  install_unattended_upgrades
  write_auto_upgrades_config
  enable_apt_timers
  info "automatic unattended upgrades are configured"
}

main "$@"
