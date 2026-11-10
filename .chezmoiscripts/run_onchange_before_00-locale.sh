#!/usr/bin/env bash
# Kills "perl: warning: Setting locale failed" everywhere, from both ends:
#  1. As ssh client: stop forwarding our LANG/LC_* to hosts that may lack them.
#     Must edit the system file: it's read after ~/.ssh/config and SendEnv accumulates.
#  2. As ssh target / local: generate every locale any of our machines uses, so
#     forwarded vars from un-fixed clients (phone, etc.) still resolve.
# Runs before other scripts, so apt in install-packages is already quiet on a fresh box.
set -euo pipefail
LOCALES=(en_US en_GB fi_FI en_DK)   # add here if a machine uses another one

SUDO=; [[ $EUID -ne 0 ]] && SUDO=sudo

f=/etc/ssh/ssh_config
if [[ -f $f ]] && grep -qE '^\s*SendEnv\s+LANG\s+LC_\*' "$f"; then
    $SUDO sed -i -E 's/^(\s*SendEnv\s+LANG\s+LC_\*)/#\1  # disabled by chezmoi, see 00-locale/' "$f"
    echo "🔧 ssh: stopped forwarding LANG/LC_* ($f)"
fi

command -v apt-get >/dev/null || exit 0   # ponytail: Debian-family only, extend when a non-Debian box appears
if [[ ! -f /etc/locale.gen ]]; then
    # LANG=C so this one apt run can't warn about the very locales it's installing
    LANG=C LC_ALL=C $SUDO apt-get install -y locales >/dev/null
fi
missing=0
for l in "${LOCALES[@]}"; do
    locale -a 2>/dev/null | grep -qix "$l.utf-\?8" || missing=1
done
if [[ $missing -eq 1 ]]; then
    re=$(IFS='|'; echo "${LOCALES[*]}")
    $SUDO sed -i -E "s/^#\s*(($re)\.UTF-8 UTF-8)/\1/" /etc/locale.gen
    LANG=C LC_ALL=C $SUDO locale-gen
fi
