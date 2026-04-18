#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo -- "$0" "$@"
fi

HELPER=/usr/local/sbin/home-snapshot
SERVICE=/etc/systemd/system/home-snapshot.service
SERVICE_NAME=home-snapshot.service
SNAPDIR=/home/.snapshots

echo "Stopping and disabling $SERVICE_NAME..."
systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true

if [[ -f "$SERVICE" ]]; then
  echo "Removing $SERVICE"
  rm -f "$SERVICE"
fi

if [[ -f "$HELPER" ]]; then
  echo "Removing $HELPER"
  rm -f "$HELPER"
fi

echo "Reloading systemd..."
systemctl daemon-reload

cat <<EOF

Uninstall complete.

Left untouched:
  $SNAPDIR
  any existing snapshots inside it

If you later want to remove snapshots manually, inspect them with:
  ls -1 $SNAPDIR

And delete one with:
  sudo btrfs subvolume delete $SNAPDIR/<snapshot-name>
EOF
