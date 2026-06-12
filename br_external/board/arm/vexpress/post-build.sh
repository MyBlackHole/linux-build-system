#!/bin/bash
# post-build.sh for ARM vexpress
# Copies kernel image and DTB to output/images

set -eu

# Allow dropbear to accept blank password root logins
mkdir -p "$TARGET_DIR/etc/default"
echo 'DROPBEAR_ARGS="-B"' > "$TARGET_DIR/etc/default/dropbear"

# Nothing extra needed - Buildroot handles vexpress DTB automatically
# when BR2_LINUX_KERNEL_INTREE_DTS_NAME is set
exit 0
