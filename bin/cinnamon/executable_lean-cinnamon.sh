#!/usr/bin/env bash

# To be removed
packages="warpinator celluloid hypnotix matrix rhythmbox transmission transmission-common thunderbird drawing simple-scan"

# Filter only installed packages
installed=$(dpkg-query -W -f='${binary:Package}\n' $packages 2>/dev/null)

# Remove them (only if any are installed)
if [ -n "$installed" ]; then
    sudo apt remove $installed
else
    echo "✅ No listed packages are installed."
fi
