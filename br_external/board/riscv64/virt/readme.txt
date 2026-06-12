RISC-V 64 QEMU virt 构建说明
================================

## 构建

```bash
cd buildroot
make BR2_EXTERNAL=../br_external linux6_riscv64_virt_defconfig O=../riscv64
make BR2_EXTERNAL=../br_external O=../riscv64
```

## 在 QEMU 中运行

```bash
qemu-system-riscv64 -M virt -m 1G \
  -kernel riscv64/images/Image \
  -drive file=riscv64/images/rootfs.ext4,if=none,format=raw,id=hd0 \
  -device virtio-blk-device,drive=hd0 \
  -append "console=ttyS0 root=/dev/vda" \
  -netdev user,id=eth0 -device virtio-net-device,netdev=eth0 \
  -nographic
```

登录提示出现后，使用 root 登录（无需密码）。
