# Linux Build System — Multi-Architecture Linux Build System

基于 Buildroot 的多架构 Linux 构建系统，支持多种 CPU 架构和 Linux 内核版本。

## 项目结构

```
linux/
├── build.sh                  # 统一构建脚本
├── br_external/              # Buildroot 外部树（自定义配置）
│   ├── Config.in
│   ├── external.desc
│   ├── external.mk
│   ├── configs/              # 13 个 defconfig（4 架构 × 多内核版本）
│   ├── board/                # 板级配置（x86_64, ARM, AArch64, RISC-V）
│   └── patches/              # 内核/GRUB2 补丁
├── buildroot/                # Buildroot 源码（已 gitignore）
├── dl/                       # 共享下载缓存
├── .ccache/                  # ccache 编译缓存（已 gitignore）
└── x86_64-*/                 # 构建输出目录（已 gitignore）
```

## 前提条件

- make, gcc, g++, bison, flex, gawk, m4
- diffutils, patch, openssl, libelf-dev
- qemu-system-x86_64 / qemu-system-arm / qemu-system-aarch64 / qemu-system-riscv64
- git, gh (GitHub CLI)

## 快速构建

```bash
# 查看所有可用配置
./build.sh list

# 构建 x86_64 + Linux 5.10
./build.sh x86_64 5.10

# 构建后运行 QEMU
./build.sh qemu x86_64 5.10

# 带端口映射（宿主机 5555 → 虚拟机 22）
./build.sh qemu x86_64 5.10 5555:22

# 带额外磁盘设备（x86_64 自动使用 IDE 接口，对应 hdb/hdc/hdd）
QEMU_EXTRA_DISKS="./1GTEST:raw" ./build.sh qemu x86_64 5.10-219
```

## QEMU 环境变量

`build.sh qemu` 支持以下环境变量自定义启动参数：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `QEMU_MEM` | 虚拟机内存大小 | `512M` |
| `QEMU_PORTS` | 端口映射（逗号分隔） | `2222:22` |
| `QEMU_DISK` | 系统盘镜像路径 | `<输出目录>/images/disk.img` |
| `QEMU_EXTRA_DISKS` | 额外磁盘列表（逗号分隔，`path:format` 格式） | 无 |

`QEMU_EXTRA_DISKS` 中 `:format` 省略时默认为 `raw`。各架构自动适配：

- **x86_64** → IDE 接口（`-hdb ./disk1 -hdc ./disk2 -hdd ./disk3`）
- **ARM vexpress** → `if=sd`（第二个 SD 控制器）
- **AArch64 / RISC-V** → `virtio-blk-device`

例如添加多个磁盘：
```bash
QEMU_EXTRA_DISKS="./data1.img:raw,./data2.qcow2:qcow2" ./build.sh qemu x86_64 6.6
```

## 支持的架构与内核版本

| 架构 | QEMU 目标 | 3.16 | 4.19 | 5.10 | 6.6 |
|------|-----------|:----:|:----:|:----:|:----:|
| **x86_64** | `qemu-system-x86_64` | ✅ | ✅ | ✅ | ✅ |
| **ARM vexpress** | `qemu-system-arm -M vexpress-a9` | ✅ | ✅ | ✅ | ✅ |
| **AArch64 virt** | `qemu-system-aarch64 -M virt` | ❌ | ✅ | ✅ | ✅ |
| **RISC-V 64 virt** | `qemu-system-riscv64 -M virt` | ❌ | ❌ | ✅ | ✅ |

## 构建配置一览

| 架构 | 内核版本 | Defconfig | 输出目录 |
|------|---------|-----------|----------|
| x86_64 | 3.16.85 | `linux3_x86_64_defconfig` | `x86_64-3.16/` |
| x86_64 | 4.19.325 | `linux4_x86_64_defconfig` | `x86_64-4.19/` |
| x86_64 | 5.10.235 | `linux5_x86_64_defconfig` | `x86_64-5.10/` |
| x86_64 | 6.6.99 | `linux6_x86_64_defconfig` | `x86_64-6.6/` |
| ARM vexpress | 3.16.85 | `linux3_arm_vexpress_defconfig` | `arm-3.16/` |
| ARM vexpress | 4.19.325 | `linux4_arm_vexpress_defconfig` | `arm-4.19/` |
| ARM vexpress | 5.10.235 | `linux5_arm_vexpress_defconfig` | `arm-5.10/` |
| ARM vexpress | 6.6.99 | `linux6_arm_vexpress_defconfig` | `arm-6.6/` |
| AArch64 virt | 4.19.325 | `linux4_aarch64_virt_defconfig` | `aarch64-4.19/` |
| AArch64 virt | 5.10.235 | `linux5_aarch64_virt_defconfig` | `aarch64-5.10/` |
| AArch64 virt | 6.6.99 | `linux6_aarch64_virt_defconfig` | `aarch64-6.6/` |
| RISC-V 64 virt | 5.10.235 | `linux5_riscv64_virt_defconfig` | `riscv64-5.10/` |
| RISC-V 64 virt | 6.6.99 | `linux6_riscv64_virt_defconfig` | `riscv64-6.6/` |

## GCC 兼容性

Linux 3.16.85 发布于 2014 年，使用 GCC 15 编译需要补丁：
- `br_external/patches/linux/3.16.85/` — GCC 14/15 兼容性修复
- `br_external/patches/linux/4.19/` — GCC 15 realmode 修复
- `br_external/patches/linux/5.10.235/` — GCC 16 realmode 修复
- Linux 6.6+ 原生支持 GCC 15/16，无需补丁
