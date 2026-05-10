#!/usr/bin/env bash
# Periodically ensure / and $HOME filesystems have at least MIN_GB GiB free.
# One critical persistent notify-send per low-space episode; clears after recovery.

set -uo pipefail

MIN_GB=10
MIN_KB=$((MIN_GB * 1024 * 1024))
INTERVAL=300

declare -A mounts_seen=()
unique_paths=()

for p in / "${HOME:-}"; do
  [[ -z "$p" || ! -e "$p" ]] && continue
  mp=$(df -Pk "$p" 2>/dev/null | awk 'NR==2 {print $6}') || continue
  [[ -z "$mp" ]] && continue
  if [[ ! -v mounts_seen[$mp] ]]; then
    mounts_seen[$mp]=1
    unique_paths+=("$p")
  fi
done

if (( ${#unique_paths[@]} == 0 )); then
  echo "disk-watch: no paths to monitor" >&2
  exit 1
fi

warned=false

while true; do
  below=false
  lines=()

  for p in "${unique_paths[@]}"; do
    avail_kb=$(df -Pk "$p" 2>/dev/null | awk 'NR==2 {print int($4)}') || true
    mp=$(df -Pk "$p" 2>/dev/null | awk 'NR==2 {print $6}')
    [[ -z "$avail_kb" || -z "$mp" ]] && continue

    if (( avail_kb < MIN_KB )); then
      below=true
      gib=$(awk -v kb="$avail_kb" 'BEGIN {printf "%.2f", kb / 1024 / 1024}')
      lines+=("$mp ($p): ${gib} GiB free")
    fi
  done

  if [[ "$below" == true ]]; then
    if [[ "$warned" == false ]]; then
      body=$(printf '%s\n' "${lines[@]}")
      DISPLAY="${DISPLAY:-:0}" notify-send \
        -u critical \
        -t 0 \
        "Disk space below ${MIN_GB} GiB" \
        "$body"
      warned=true
    fi
  else
    warned=false
  fi

  sleep "$INTERVAL"
done
