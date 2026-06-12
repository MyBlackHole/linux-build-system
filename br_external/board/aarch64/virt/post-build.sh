#!/bin/bash
# post-build.sh for AArch64 virt
set -eu

BOARD_DIR=$(dirname "$0")

# Install pre-generated dropbear host keys (avoid entropy stall on first boot)
# dropbear.mk creates /etc/dropbear as symlink -> /var/run/dropbear; replace with dir
rm -f "$TARGET_DIR/etc/dropbear"
mkdir -p "$TARGET_DIR/etc/dropbear"
cp -f "$BOARD_DIR/../../dropbear/dropbear_"*_host_key "$TARGET_DIR/etc/dropbear/"

# Allow dropbear to accept blank password root logins
mkdir -p "$TARGET_DIR/etc/default"
echo 'DROPBEAR_ARGS="-B"' > "$TARGET_DIR/etc/default/dropbear"

exit 0
