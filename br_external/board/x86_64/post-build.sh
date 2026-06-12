#!/bin/sh
set -e

BOARD_DIR=$(dirname "$0")
TARGET_DIR=$1

# Install pre-generated dropbear host keys (avoid entropy stall on first boot)
# dropbear.mk creates /etc/dropbear as symlink -> /var/run/dropbear; replace with dir
rm -f "$TARGET_DIR/etc/dropbear"
mkdir -p "$TARGET_DIR/etc/dropbear"
cp -f "$BOARD_DIR/../dropbear/dropbear_"*_host_key "$TARGET_DIR/etc/dropbear/"

# Allow dropbear to accept blank password root logins
mkdir -p "$TARGET_DIR/etc/default"
echo 'DROPBEAR_ARGS="-B"' > "$TARGET_DIR/etc/default/dropbear"

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
