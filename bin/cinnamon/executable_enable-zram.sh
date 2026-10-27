#!/usr/bin/env bash
set -euo pipefail

# Proxmox (and other root-only hosts) ship without sudo
if [[ $EUID -eq 0 ]]; then
    SUDO=""
elif command -v sudo &>/dev/null; then
    SUDO="sudo"
else
    echo "❌ Run as root or install sudo." >&2
    exit 1
fi

if ! dpkg -s systemd-zram-generator &>/dev/null; then
    echo "📦 Installing zram generator..."
    $SUDO apt update || true
    $SUDO apt install -y systemd-zram-generator
else
    echo "📦 zram generator already installed, skipping."
fi

CONFIG_FILE="/etc/systemd/zram-generator.conf"

echo "💾 Writing configuration to $CONFIG_FILE..."

# Backup if exists
if [[ -f "$CONFIG_FILE" ]]; then
    $SUDO cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%s)"
fi

# Create config
$SUDO tee "$CONFIG_FILE" > /dev/null <<'EOF'
[zram0]
# Use up to 50% of RAM for zram
zram-size = ram / 2

# Compression algorithm (zstd is best modern default)
compression-algorithm = zstd

# Swap priority (higher than disk swap)
swap-priority = 100
EOF

echo "🔧 Reloading systemd daemon..."
$SUDO systemctl daemon-reload

echo "🔧 Starting zram swap..."
# Tear down existing zram swap before restarting the setup service (idempotency)
if swapon --show | grep -q '/dev/zram0'; then
    $SUDO swapoff /dev/zram0 || true
fi
$SUDO systemctl stop systemd-zram-setup@zram0.service 2>/dev/null || true
# Reset the zram device if it exists so the generator can reconfigure it
if [[ -e /sys/block/zram0/reset ]]; then
    echo 1 | $SUDO tee /sys/block/zram0/reset > /dev/null
fi
$SUDO systemctl start systemd-zram-setup@zram0.service

# Wait briefly for the swap to become active
for i in 1 2 3 4 5; do
    swapon --show | grep -q '/dev/zram0' && break
    sleep 1
done

if ! swapon --show | grep -q '/dev/zram0'; then
    echo "❌ zram0 failed to start. Service status:"
    systemctl status systemd-zram-setup@zram0.service --no-pager || true
    exit 1
fi

echo "🔧 Verifying zram device..."
if swapon --show | grep -q '/dev/zram0'; then
    ZRAM_SIZE=$(swapon --show --noheadings --bytes | awk '/\/dev\/zram0/ {printf "%.0f", $3/1024/1024}')
    ZRAM_USED=$(swapon --show --noheadings --bytes | awk '/\/dev\/zram0/ {printf "%.0f", $4/1024/1024}')
    echo "✅ zram0 is active: ${ZRAM_SIZE} MB swap in RAM, ${ZRAM_USED} MB used"
else
    echo "⚠️  zram0 is NOT active as swap"
fi

# Show any other swap devices for context
OTHER=$(swapon --show --noheadings | grep -v '/dev/zram0' || true)
if [[ -n "$OTHER" ]]; then
    echo "ℹ️  Other swap devices:"
    while IFS= read -r line; do
        NAME=$(awk '{print $1}' <<< "$line")
        TYPE=$(awk '{print $2}' <<< "$line")
        SIZE=$(awk '{print $3}' <<< "$line")
        USED=$(awk '{print $4}' <<< "$line")
        PRIO=$(awk '{print $5}' <<< "$line")
        echo "   $NAME ($TYPE): ${SIZE} total, ${USED} used, priority $PRIO"
    done <<< "$OTHER"
fi

echo "🏆 Done."
