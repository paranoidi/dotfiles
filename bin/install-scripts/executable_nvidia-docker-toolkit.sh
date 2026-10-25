#!/bin/bash
set -euo pipefail

# NVIDIA repo GPG key
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

# Use official NVIDIA .list template — $(ARCH) substituted by apt
sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null <<'EOF'
deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/$(ARCH) /
EOF

sudo apt update
sudo apt install -y nvidia-container-toolkit
sudo systemctl restart docker

# Test
echo 'Testing...'
docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi
