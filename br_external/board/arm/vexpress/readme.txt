ARM vexpress (Cortex-A9) 构建说明
=====================================

## 构建

```bash
cd buildroot
make BR2_EXTERNAL=../br_external linux6_arm_vexpress_defconfig O=../arm
make BR2_EXTERNAL=../br_external O=../arm
```

## 在 QEMU 中运行

```bash
qemu-system-arm -M vexpress-a9 -m 256 \
  -kernel arm/images/zImage \
  -dtb arm/images/vexpress-v2p-ca9.dtb \
  -drive file=arm/images/rootfs.ext4,if=sd,format=raw \
  -append "console=ttyAMA0 root=/dev/mmcblk0" \
  -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 \
  -nographic
```

登录提示出现后，使用 root 登录（无需密码）。
