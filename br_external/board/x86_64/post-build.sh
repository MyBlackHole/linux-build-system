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
cp -f "$BOARD_DIR/../openssh/ssh_host_"*"_key" "$TARGET_DIR/etc/ssh/"
cp -f "$BOARD_DIR/../openssh/ssh_host_"*"_key.pub" "$TARGET_DIR/etc/ssh/"
chmod 600 "$TARGET_DIR/etc/ssh/ssh_host_"*"_key"

# Allow root login with empty password for development
# Guard against duplicate appends on rebuild
grep -q '^PermitRootLogin yes$' "$TARGET_DIR/etc/ssh/sshd_config" 2>/dev/null || \
	echo 'PermitRootLogin yes' >> "$TARGET_DIR/etc/ssh/sshd_config"
grep -q '^PermitEmptyPasswords yes$' "$TARGET_DIR/etc/ssh/sshd_config" 2>/dev/null || \
	echo 'PermitEmptyPasswords yes' >> "$TARGET_DIR/etc/ssh/sshd_config"

# Ensure /etc/shadow root entry has proper format for glibc getspnam_r
# Format: root::0:0:99999:7:::   (empty password, never expires)
# Root cause: Buildroot with empty BR2_TARGET_GENERIC_ROOT_PASSWD="" produces
# root:::::::: (all empty fields) which confuses glibc's getspnam_r parser.
# When getspnam_r fails, both Busybox login AND OpenSSH deny access.
sed -i 's/^root:[^:]*:.*$/root::0:0:99999:7:::/' "$TARGET_DIR/etc/shadow"

# Create /etc/securetty for root login on serial console
# Busybox with FEATURE_SECURETTY needs this file for uid 0
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

# Install GRUB BIOS config
mkdir -p "$TARGET_DIR/boot/grub"
cp -f "$BOARD_DIR/grub-bios.cfg" "$TARGET_DIR/boot/grub/grub.cfg"

# Copy GRUB 1st stage boot image to binaries for genimage.
# Note: BINARIES_DIR is NOT passed to post-build scripts; derive it from TARGET_DIR.
BINARIES_DIR=$(readlink -f "$TARGET_DIR/../images")
cp -f "$TARGET_DIR/lib/grub/i386-pc/boot.img" "$BINARIES_DIR"

# Patch boot.img's firstlist to point to LBA 1 (offset 512) where grub.img starts.
# Without this, boot.img doesn't know where to find core.img and won't boot.
GRUB_IMG="$BINARIES_DIR/grub.img"
if [ -f "$GRUB_IMG" ]; then
    GRUB_SIZE=$(stat -c%s "$GRUB_IMG")
    GRUB_SECTORS=$(( (GRUB_SIZE + 511) / 512 ))
    # firstlist.lba at offset 0x1B0 = LBA 1 (start of embed area)
    printf '\001\000\000\000' | dd of="$BINARIES_DIR/boot.img" bs=1 seek=$((0x1B0)) conv=notrunc status=none 2>/dev/null
    # firstlist.count at offset 0x1B4 = number of 512-byte sectors of grub.img
    printf "\\$(printf '%03o' $((GRUB_SECTORS & 0xFF)))\\$(printf '%03o' $(((GRUB_SECTORS>>8) & 0xFF)))\\$(printf '%03o' 0)\\$(printf '%03o' 0)" | \
        dd of="$BINARIES_DIR/boot.img" bs=1 seek=$((0x1B4)) conv=notrunc status=none 2>/dev/null
    echo "boot.img: firstlist patched (LBA=1, sectors=${GRUB_SECTORS})"
else
    echo "WARNING: grub.img not found in $BINARIES_DIR, cannot patch boot.img" >&2
fi
