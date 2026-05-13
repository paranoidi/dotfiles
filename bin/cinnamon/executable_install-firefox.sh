#!/usr/bin/env bash
set -euo pipefail

KEYRING_DIR="/etc/apt/keyrings"
KEY_FILE="$KEYRING_DIR/packages.mozilla.org.asc"
EXPECTED_FINGERPRINT="35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3"

# Ensure wget is available
if ! command -v wget &>/dev/null; then
    echo "wget not found, installing..."
    sudo apt-get install -y wget
fi

# Create keyrings directory
sudo install -d -m 0755 "$KEYRING_DIR"

# Import Mozilla APT repository signing key
echo "Importing Mozilla APT repository signing key..."
wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | sudo tee "$KEY_FILE" > /dev/null

# Verify key fingerprint
echo "Verifying key fingerprint..."
GNUPGHOME=$(mktemp -d)
gpg --homedir "$GNUPGHOME" -n -q --import --import-options import-show "$KEY_FILE" \
    | awk '/pub/{getline; gsub(/^ +| +$/,""); if($0 == "'"$EXPECTED_FINGERPRINT"'") print "\nThe key fingerprint matches ("$0").\n"; else { print "\nVerification failed: the fingerprint ("$0") does not match the expected one.\n"; exit 1 }}'
rm -rf "$GNUPGHOME"

# Add Mozilla APT repository
echo "Adding Mozilla APT repository..."
cat <<EOF | sudo tee /etc/apt/sources.list.d/mozilla.sources > /dev/null
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: $KEY_FILE
EOF

# Configure APT priority
echo "Configuring APT priority for Mozilla repository..."
cat <<EOF | sudo tee /etc/apt/preferences.d/mozilla > /dev/null
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000
EOF

# Update and install Firefox
echo "Updating package lists..."
sudo apt-get update

echo "Installing Firefox..."
sudo apt-get install -y firefox

echo "Done! Firefox has been installed from the Mozilla APT repository."
