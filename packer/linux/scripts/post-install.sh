#!/bin/bash
set -euo pipefail

# Runs after Packer connects via SSH as 'packer' user.
# sudoers entry already created by preseed late_command — use sudo here.

# Ensure SSH allows password auth (Ansible will switch to keys per-lab)
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# Install Python3 and QEMU guest agent
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends python3 python3-pip qemu-guest-agent

# Zero free disk space for better template compression
sudo dd if=/dev/zero of=/tmp/zero bs=1M 2>/dev/null || true
sudo rm -f /tmp/zero

# Clean apt cache
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

echo "Post-install complete."
