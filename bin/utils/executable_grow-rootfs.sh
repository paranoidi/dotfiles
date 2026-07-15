#!/usr/bin/env bash
set -euo pipefail

# grow-rootfs.sh
# Grow a filesystem to use all free space on its underlying disk.
# Walks the whole stack: partition -> (LUKS) -> (LVM PV/LV) -> filesystem.
# Supports plain partitions, LUKS-encrypted, and LVM-on-LUKS layouts.
# Grows ext2/3/4, xfs and btrfs filesystems online where possible.

die() {
  echo "error: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

warn() {
  echo "warning: $*" >&2
}

as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    command -v sudo >/dev/null 2>&1 || die "sudo is required when not running as root"
    sudo "$@"
  fi
}

confirm() {
  # $1: prompt. Returns 0 on yes.
  local reply
  read -r -p "$1 [y/N] " reply
  [[ "${reply}" =~ ^[Yy]([Ee][Ss])?$ ]]
}

require_cmds() {
  local c
  for c in "$@"; do
    command -v "${c}" >/dev/null 2>&1 || die "required command not found: ${c}"
  done
}

# Relocate the GPT backup header/table to the end of a (possibly enlarged)
# disk. When a disk is grown, the backup GPT is left mid-disk and partition
# tools stop to ask "Fix/Ignore?"; doing this up front makes the whole run
# non-interactive. No-op on MBR disks or when sgdisk is unavailable.
fix_gpt_backup() {
  local dsk="$1"
  command -v sgdisk >/dev/null 2>&1 || return 0
  [[ "$(blk_prop "${dsk}" PTTYPE)" == "gpt" ]] || return 0
  info "Relocating GPT backup header to end of ${dsk} ..."
  as_root sgdisk --move-second-header "${dsk}" >/dev/null 2>&1 \
    || as_root sgdisk -e "${dsk}" >/dev/null 2>&1 \
    || warn "could not relocate GPT backup header (continuing anyway)"
}

# Resolve the whole device dependency chain (parents) for a given device
# using lsblk, returning kernel names from the top-most parent downwards.
# Usage: chain=($(device_chain <kname>))
device_chain() {
  local target="$1"
  lsblk -s -n -o NAME -p "${target}" | grep -oE '/dev/[^[:space:]]+'
}

# Get a single property for a device via lsblk.
blk_prop() {
  # $1: device path, $2: column (e.g. TYPE, PKNAME, FSTYPE, NAME)
  lsblk -n -d -o "$2" -p "$1" 2>/dev/null | head -n1 | awk '{$1=$1; print}'
}

usage() {
  cat <<'EOF'
Usage: grow-rootfs.sh [MOUNTPOINT|DEVICE]

Grow a filesystem to consume all free space on its underlying disk.

Arguments:
  MOUNTPOINT|DEVICE   Target to grow. Defaults to "/" (the root filesystem).
                      May be a mountpoint (e.g. /) or a block device
                      (e.g. /dev/mapper/vg-root).

The script prints a summary of every action it will take and asks for
explicit confirmation before making any changes. If more than one disk is
involved it asks you to choose.
EOF
}

main() {
  case "${1:-}" in
    -h | --help)
      usage
      exit 0
      ;;
  esac

  require_cmds lsblk findmnt awk sed grep

  local target="${1:-/}"
  local fs_dev fstype mountpoint

  # Resolve target to a filesystem block device + mountpoint.
  if [[ -b "${target}" ]]; then
    fs_dev="$(findmnt -n -o SOURCE --first-only "${target}" 2>/dev/null || true)"
    fs_dev="${fs_dev:-${target}}"
    mountpoint="$(findmnt -n -o TARGET --first-only --source "${fs_dev}" 2>/dev/null || true)"
  else
    fs_dev="$(findmnt -n -o SOURCE --target "${target}" 2>/dev/null || true)"
    [[ -n "${fs_dev}" ]] || die "'${target}' is not a mountpoint or block device"
    mountpoint="$(findmnt -n -o TARGET --target "${target}" 2>/dev/null || true)"
  fi

  fstype="$(findmnt -n -o FSTYPE --source "${fs_dev}" 2>/dev/null || blk_prop "${fs_dev}" FSTYPE)"
  info "Target filesystem device: ${fs_dev}"
  info "Mountpoint:               ${mountpoint:-<none>}"
  info "Filesystem type:          ${fstype:-<unknown>}"

  case "${fstype}" in
    ext2 | ext3 | ext4 | xfs | btrfs) ;;
    *) die "unsupported filesystem type '${fstype}' (supported: ext2/3/4, xfs, btrfs)" ;;
  esac

  # Walk the chain from the fs device down to the physical disk(s).
  mapfile -t chain < <(device_chain "${fs_dev}")
  [[ "${#chain[@]}" -gt 0 ]] || die "could not resolve device chain for ${fs_dev}"

  # Identify the physical disk(s) at the bottom of the chain.
  local disks=()
  local d t
  for d in "${chain[@]}"; do
    t="$(blk_prop "${d}" TYPE)"
    if [[ "${t}" == "disk" ]]; then
      disks+=("${d}")
    fi
  done
  [[ "${#disks[@]}" -gt 0 ]] || die "could not identify a physical disk backing ${fs_dev}"

  # Choose a disk if multiple are involved (e.g. LVM spanning disks).
  local disk
  if [[ "${#disks[@]}" -eq 1 ]]; then
    disk="${disks[0]}"
  else
    warn "Multiple disks back this filesystem: ${disks[*]}"
    echo "Select the disk whose free space should be added:"
    local i=1 choice
    for d in "${disks[@]}"; do
      printf '  %d) %s (%s)\n' "${i}" "${d}" "$(blk_prop "${d}" SIZE)"
      i=$((i + 1))
    done
    read -r -p "Enter number [1-${#disks[@]}]: " choice
    if ! [[ "${choice}" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#disks[@]})); then
      die "invalid selection"
    fi
    disk="${disks[$((choice - 1))]}"
  fi
  info "Using physical disk: ${disk}"

  # Find the partition on ${disk} that is part of our chain.
  local part=""
  for d in "${chain[@]}"; do
    if [[ "$(blk_prop "${d}" TYPE)" == "part" && "$(blk_prop "${d}" PKNAME)" == "${disk}" ]]; then
      part="${d}"
      break
    fi
  done
  [[ -n "${part}" ]] || die "could not find the partition on ${disk} within the chain"

  # Partition number = trailing digits of the partition device name.
  local partnum
  partnum="$(echo "${part}" | grep -oE '[0-9]+$' || true)"
  [[ -n "${partnum}" ]] || die "could not determine partition number for ${part}"

  # Identify optional LUKS and LVM layers in the chain.
  local luks_dev="" lvm_lv="" lvm_pv="" lvm_vg=""
  for d in "${chain[@]}"; do
    t="$(blk_prop "${d}" TYPE)"
    case "${t}" in
      crypt) luks_dev="${d}" ;;
      lvm) lvm_lv="${d}" ;;
    esac
  done

  if [[ -n "${lvm_lv}" ]]; then
    require_cmds lvextend pvresize lvs vgs pvs
    lvm_vg="$(as_root lvs --noheadings -o vg_name "${lvm_lv}" 2>/dev/null | awk '{$1=$1; print}')" || true
    # The PV sits directly above the partition/LUKS layer.
    if [[ -n "${luks_dev}" ]]; then
      lvm_pv="${luks_dev}"
    else
      lvm_pv="${part}"
    fi
  fi

  # Detect the partition-growing tool.
  local grow_tool=""
  if command -v growpart >/dev/null 2>&1; then
    grow_tool="growpart"
  elif command -v parted >/dev/null 2>&1; then
    grow_tool="parted"
  else
    die "need 'growpart' (cloud-guest-utils) or 'parted' to grow the partition"
  fi

  if [[ -n "${luks_dev}" ]]; then
    require_cmds cryptsetup
  fi

  # --- Summary -------------------------------------------------------------
  echo
  echo "=================== PLANNED ACTIONS ==================="
  echo "Physical disk        : ${disk} ($(blk_prop "${disk}" SIZE))"
  echo "Partition to grow    : ${part} (number ${partnum})"
  [[ -n "${luks_dev}" ]] && echo "LUKS container       : ${luks_dev}"
  if [[ -n "${lvm_lv}" ]]; then
    echo "LVM physical volume  : ${lvm_pv}"
    echo "LVM volume group     : ${lvm_vg}"
    echo "LVM logical volume   : ${lvm_lv}"
  fi
  echo "Filesystem           : ${fs_dev} (${fstype}, mounted at ${mountpoint:-<none>})"
  echo
  echo "Steps that will run (as root):"
  local step=1
  if [[ "${grow_tool}" == "growpart" ]]; then
    echo "  ${step}. growpart ${disk} ${partnum} (auto-fixes GPT, non-interactive)"; step=$((step + 1))
  else
    if command -v sgdisk >/dev/null 2>&1; then
      echo "  ${step}. sgdisk --move-second-header ${disk} (relocate GPT backup to end of disk)"; step=$((step + 1))
    fi
    echo "  ${step}. parted -s ${disk} resizepart ${partnum} 100% (script mode, non-interactive)"; step=$((step + 1))
  fi
  echo "  ${step}. partprobe ${disk} (refresh kernel partition table)"; step=$((step + 1))
  if [[ -n "${luks_dev}" ]]; then
    local cname="${luks_dev#/dev/mapper/}"
    echo "  ${step}. cryptsetup resize ${cname}"; step=$((step + 1))
  fi
  if [[ -n "${lvm_lv}" ]]; then
    echo "  ${step}. pvresize ${lvm_pv}"; step=$((step + 1))
    echo "  ${step}. lvextend -l +100%FREE ${lvm_lv}"; step=$((step + 1))
  fi
  case "${fstype}" in
    ext2 | ext3 | ext4) echo "  ${step}. resize2fs ${fs_dev}" ;;
    xfs) echo "  ${step}. xfs_growfs ${mountpoint}" ;;
    btrfs) echo "  ${step}. btrfs filesystem resize max ${mountpoint}" ;;
  esac
  echo "======================================================"
  echo
  warn "This modifies the partition table of ${disk}. Ensure you have a backup."
  echo
  confirm "Proceed with the actions above?" || die "aborted by user"

  # --- Execute -------------------------------------------------------------
  info "Growing partition ${part} ..."
  if [[ "${grow_tool}" == "growpart" ]]; then
    # growpart exits 1 with "NOCHANGE" when already at max; tolerate that.
    if ! as_root growpart "${disk}" "${partnum}"; then
      warn "growpart reported no change (partition may already fill the disk)"
    fi
  else
    # Relocate the GPT backup header first so parted never stops to ask
    # "Fix/Ignore?", then resize in non-interactive script mode.
    fix_gpt_backup "${disk}"
    if ! as_root parted -s "${disk}" resizepart "${partnum}" 100%; then
      warn "parted script mode failed; retrying with automatic 'Fix' answers"
      printf 'Fix\nFix\n' | as_root parted ---pretend-input-tty "${disk}" \
        resizepart "${partnum}" 100%
    fi
  fi

  info "Refreshing kernel partition table ..."
  if command -v partprobe >/dev/null 2>&1; then
    as_root partprobe "${disk}" || true
  else
    as_root udevadm settle || true
  fi
  sleep 1

  if [[ -n "${luks_dev}" ]]; then
    info "Resizing LUKS container ${luks_dev} ..."
    as_root cryptsetup resize "${luks_dev#/dev/mapper/}"
  fi

  if [[ -n "${lvm_lv}" ]]; then
    info "Resizing LVM physical volume ${lvm_pv} ..."
    as_root pvresize "${lvm_pv}"
    info "Extending logical volume ${lvm_lv} to use all free space ..."
    as_root lvextend -l +100%FREE "${lvm_lv}"
  fi

  info "Growing filesystem (${fstype}) ..."
  case "${fstype}" in
    ext2 | ext3 | ext4) as_root resize2fs "${fs_dev}" ;;
    xfs) as_root xfs_growfs "${mountpoint}" ;;
    btrfs) as_root btrfs filesystem resize max "${mountpoint}" ;;
  esac

  echo
  info "Done. New filesystem usage:"
  df -hT "${mountpoint:-${fs_dev}}"
}

main "$@"
