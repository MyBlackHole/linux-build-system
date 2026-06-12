#!/bin/bash
# post-build.sh for ARM vexpress
# Copies kernel image and DTB to output/images

set -eu

BOARD_DIR=$(dirname "$0")

# Install pre-generated dropbear host keys (avoid entropy stall on first boot)
mkdir -p "$TARGET_DIR/etc/dropbear"
cp -f "$BOARD_DIR/../../dropbear/dropbear_"*_host_key "$TARGET_DIR/etc/dropbear/"

# Allow dropbear to accept blank password root logins
mkdir -p "$TARGET_DIR/etc/default"
echo 'DROPBEAR_ARGS="-B"' > "$TARGET_DIR/etc/default/dropbear"

# Nothing extra needed - Buildroot handles vexpress DTB automatically
# when BR2_LINUX_KERNEL_INTREE_DTS_NAME is set
exit 0
