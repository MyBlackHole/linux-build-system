#!/bin/sh
set -e

BOARD_DIR=$(dirname "$0")
TARGET_DIR=$1

# Install pre-generated OpenSSH host keys (avoid entropy stall on first boot)
mkdir -p "$TARGET_DIR/etc/ssh"
cp -f "$BOARD_DIR/../../openssh/ssh_host_"*"_key" "$TARGET_DIR/etc/ssh/"
cp -f "$BOARD_DIR/../../openssh/ssh_host_"*"_key.pub" "$TARGET_DIR/etc/ssh/"
chmod 600 "$TARGET_DIR/etc/ssh/ssh_host_"*"_key"

# Allow root login with empty password for development
cat >> "$TARGET_DIR/etc/ssh/sshd_config" << 'EOF'
PermitRootLogin yes
PermitEmptyPasswords yes
EOF
