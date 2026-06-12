#!/bin/bash
# post-build.sh for RISC-V 64 virt
set -eu

# Allow dropbear to accept blank password root logins
mkdir -p "$TARGET_DIR/etc/default"
echo 'DROPBEAR_ARGS="-B"' > "$TARGET_DIR/etc/default/dropbear"

exit 0
