#!/bin/sh
set -e

BOARD_DIR=$(dirname "$0")
TARGET_DIR=$1

# Remove stale Dropbear files (from old configs where DROPBEAR was enabled)
# Dropbear conflicts with OpenSSH on port 22; OpenSSH (sshd) is the intended server.
rm -f "$TARGET_DIR/etc/init.d/S50dropbear"
rm -rf "$TARGET_DIR/etc/dropbear"
rm -f "$TARGET_DIR/usr/sbin/dropbear"
rm -f "$TARGET_DIR/usr/bin/dropbearkey"
rm -f "$TARGET_DIR/usr/bin/dropbearconvert"

# Install pre-generated OpenSSH host keys (avoid entropy stall on first boot)
mkdir -p "$TARGET_DIR/etc/ssh"
cp -f "$BOARD_DIR/../../openssh/ssh_host_"*"_key" "$TARGET_DIR/etc/ssh/"
cp -f "$BOARD_DIR/../../openssh/ssh_host_"*"_key.pub" "$TARGET_DIR/etc/ssh/"
chmod 600 "$TARGET_DIR/etc/ssh/ssh_host_"*"_key"

# Allow root login with empty password for development
grep -q '^PermitRootLogin yes$' "$TARGET_DIR/etc/ssh/sshd_config" 2>/dev/null || \
	echo 'PermitRootLogin yes' >> "$TARGET_DIR/etc/ssh/sshd_config"
grep -q '^PermitEmptyPasswords yes$' "$TARGET_DIR/etc/ssh/sshd_config" 2>/dev/null || \
	echo 'PermitEmptyPasswords yes' >> "$TARGET_DIR/etc/ssh/sshd_config"

# Ensure /etc/shadow root entry has proper format for glibc getspnam_r
sed -i 's/^root:[^:]*:.*$/root::0:0:99999:7:::/' "$TARGET_DIR/etc/shadow"

# Create /etc/securetty for root login on serial console
if [ ! -f "$TARGET_DIR/etc/securetty" ]; then
	{
		echo 'console'
		echo 'ttyS0'
		echo 'tty1'
	} > "$TARGET_DIR/etc/securetty"
fi

# Speed up SSH: disable DNS resolution for client connections
grep -q '^UseDNS no$' "$TARGET_DIR/etc/ssh/sshd_config" 2>/dev/null || \
	echo 'UseDNS no' >> "$TARGET_DIR/etc/ssh/sshd_config"
