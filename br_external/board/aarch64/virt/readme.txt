AArch64 (ARM64) QEMU virt 构建说明
======================================

## 构建

```bash
cd buildroot
make BR2_EXTERNAL=../br_external linux6_aarch64_virt_defconfig O=../aarch64
make BR2_EXTERNAL=../br_external O=../aarch64
```

## 在 QEMU 中运行

```bash
qemu-system-aarch64 -M virt -cpu cortex-a53 -m 1G \
  -kernel aarch64/images/Image \
  -drive file=aarch64/images/rootfs.ext4,if=none,format=raw,id=hd0 \
  -device virtio-blk-device,drive=hd0 \
  -append "console=ttyAMA0 root=/dev/vda" \
  -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 \
  -nographic
```

登录提示出现后，使用 root 登录（无需密码）。
