#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  exec sudo -- "$0" "$@"
fi

HELPER=/usr/local/sbin/home-snapshot
SERVICE=/etc/systemd/system/home-snapshot.service
SNAPDIR=/home/.snapshots

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: required command not found: $1" >&2
    exit 1
  }
}

need btrfs
need findmnt
need systemctl
need flock
need find
need grep
need sort

echo "Checking /home..."

fstype="$(findmnt -n -o FSTYPE /home || true)"
if [[ "$fstype" != "btrfs" ]]; then
  echo "Error: /home is not mounted as btrfs" >&2
  exit 1
fi

if ! btrfs subvolume show /home >/dev/null 2>&1; then
  echo "Error: /home is not a Btrfs subvolume" >&2
  echo "You need /home to be its own subvolume for this setup." >&2
  exit 1
fi

if [[ -e "$SNAPDIR" ]]; then
  if [[ ! -d "$SNAPDIR" ]]; then
    echo "Error: $SNAPDIR exists but is not a directory" >&2
    echo "Move/remove it and re-run this installer." >&2
    exit 1
  fi

  snapdir_fstype="$(findmnt -n -T "$SNAPDIR" -o FSTYPE || true)"
  if [[ "$snapdir_fstype" != "btrfs" ]]; then
    echo "Error: $SNAPDIR is not on a Btrfs filesystem" >&2
    echo "Move/remove it and re-run this installer." >&2
    exit 1
  fi

  echo "Using existing snapshot directory: $SNAPDIR"
else
  echo "Creating snapshot directory: $SNAPDIR"
  install -d -m 755 "$SNAPDIR"
fi

echo "Installing helper: $HELPER"
install -d -m 755 /usr/local/sbin
cat > "$HELPER" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SNAPDIR=/home/.snapshots
KEEP=30
LOCK=/run/home-snapshot.lock

BTRFS="$(command -v btrfs)"
FLOCK="$(command -v flock)"

STAMP="$(date +%Y-%m-%d-%H%M%S)"
NAME="boot-$STAMP"

install -d -m 755 "$SNAPDIR"

exec 9>"$LOCK"
"$FLOCK" -n 9 || exit 0

"$BTRFS" subvolume snapshot -r /home "$SNAPDIR/$NAME"

mapfile -t snaps < <(
  find "$SNAPDIR" -mindepth 1 -maxdepth 1 -printf '%f\n' \
    | grep '^boot-' \
    | sort || true
)

excess=$((${#snaps[@]} - KEEP))
if (( excess > 0 )); then
  for old in "${snaps[@]:0:excess}"; do
    "$BTRFS" subvolume delete "$SNAPDIR/$old"
  done
fi
EOF

chown root:root "$HELPER"
chmod 755 "$HELPER"

echo "Installing systemd unit: $SERVICE"
cat > "$SERVICE" <<'EOF'
[Unit]
Description=Create read-only Btrfs snapshot of /home at boot
DefaultDependencies=no
After=local-fs.target
Before=systemd-user-sessions.service
ConditionPathIsDirectory=/home
ConditionPathIsDirectory=/home/.snapshots

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/home-snapshot

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable home-snapshot.service

echo
echo "Installed successfully."
echo
echo "Test it now with:"
echo "  sudo systemctl start home-snapshot.service"
echo
echo "Check snapshots with:"
echo "  ls -1 /home/.snapshots"
echo
echo "On each boot, one read-only snapshot will be created."
echo "Retention is currently KEEP=30 in $HELPER"
