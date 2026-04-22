#!/usr/bin/env bash
#
# This can be used to migrate chezmoi repository to personal account.
# It works by switching git origin to ssh which does not use git credential helper.
# It will create ssh host alias and enable given key for that and update repository origin.
set -euo pipefail

# ----------------------------
# Args
# ----------------------------
KEY_PATH="${1:-}"
ALIAS="${2:-}"

if [[ -z "$KEY_PATH" || -z "$ALIAS" ]]; then
  echo "Usage: $0 <ssh-key-path> <github-host-alias>"
  exit 1
fi

# ----------------------------
# Ensure repo root
# ----------------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
CURRENT_DIR="$(pwd)"

if [[ -z "$REPO_ROOT" ]]; then
  echo "Error: not inside a git repository."
  exit 1
fi

if [[ "$REPO_ROOT" != "$CURRENT_DIR" ]]; then
  echo "Error: must be executed from repository root: $REPO_ROOT"
  exit 1
fi

# ----------------------------
# Extract origin URL
# ----------------------------
ORIGIN_URL="$(git config --get remote.origin.url)"

if [[ -z "$ORIGIN_URL" ]]; then
  echo "Error: no remote.origin.url found"
  exit 1
fi

# ----------------------------
# Parse GitHub owner/repo from URL
# Supports:
#   git@github.com:OWNER/REPO.git
#   https://github.com/OWNER/REPO.git
# ----------------------------
OWNER_REPO="$(
  echo "$ORIGIN_URL" \
  | sed -E 's#.*github\.com[:/]+##' \
  | sed -E 's#\.git$##'
)"

OWNER="$(echo "$OWNER_REPO" | cut -d/ -f1)"
REPO="$(echo "$OWNER_REPO" | cut -d/ -f2)"

if [[ -z "$OWNER" || -z "$REPO" ]]; then
  echo "Error: failed to parse owner/repo from origin URL: $ORIGIN_URL"
  exit 1
fi

echo "Detected repo:"
echo "  Owner: $OWNER"
echo "  Repo : $REPO"

# ----------------------------
# Ensure SSH key exists
# ----------------------------
if [[ ! -f "$KEY_PATH" ]]; then
  echo "Error: SSH key not found at $KEY_PATH"
  exit 1
fi

# ----------------------------
# Update ~/.ssh/config
# ----------------------------
SSH_CONFIG="$HOME/.ssh/config"
mkdir -p "$(dirname "$SSH_CONFIG")"
touch "$SSH_CONFIG"

if ! grep -q "Host $ALIAS" "$SSH_CONFIG"; then
  cat >> "$SSH_CONFIG" <<EOF

Host $ALIAS
  HostName github.com
  User git
  IdentityFile $KEY_PATH
  IdentitiesOnly yes
EOF
else
  echo "SSH alias '$ALIAS' already exists in config (not modifying)."
fi

# ----------------------------
# Switch repo remote to alias
# ----------------------------
NEW_URL="git@$ALIAS:$OWNER/$REPO.git"

echo "Setting origin to: $NEW_URL"
git remote set-url origin "$NEW_URL"

echo "Done."
echo "You can now push without gh auth switching."
