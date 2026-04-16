# Define the package list (edit this line as needed)
packages="warpinator celluloid hypnotix matrix rhythmbox transmission thunderbird drawing"

# Filter only installed packages
installed=$(dpkg-query -W -f='${binary:Package}\n' $packages 2>/dev/null)

# Remove them (only if any are installed)
if [ -n "$installed" ]; then
    sudo apt remove $installed
else
    echo "✅ No listed packages are installed."
fi
