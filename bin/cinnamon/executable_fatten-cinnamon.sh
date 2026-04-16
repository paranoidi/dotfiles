# -------------------------
# APT packages (edit here)
# -------------------------
apt_packages=""

# -------------------------
# Flatpak packages (edit here)
# Use full Flatpak IDs
# -------------------------
flatpak_packages="com.spotify.Client com.discordapp.Discord"

# -------------------------
# APT: filter valid + not installed
# -------------------------
apt_to_install=$(
  for pkg in $apt_packages; do
    if apt-cache show "$pkg" >/dev/null 2>&1 && ! dpkg -s "$pkg" >/dev/null 2>&1; then
      echo "$pkg"
    fi
  done
)

# Install APT packages if any
if [ -n "$apt_to_install" ]; then
    sudo apt update
    sudo apt install -y $apt_to_install
else
    echo "❌ No APT packages to install."
fi

# -------------------------
# Flatpak: filter not installed
# -------------------------
flatpak_to_install=$(
  for pkg in $flatpak_packages; do
    if ! flatpak list --app --columns=application | grep -qx "$pkg"; then
      echo "$pkg"
    fi
  done
)

# Install Flatpak packages if any
if [ -n "$flatpak_to_install" ]; then
    flatpak install -y flathub $flatpak_to_install
else
    echo "❌ No Flatpak packages to install."
fi
