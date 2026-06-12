#!/bin/bash
# Linux3 多架构多版本构建脚本
# 用法: ./build.sh <架构> [内核版本]
#
# 架构: x86_64, arm, aarch64, riscv64
# 内核版本: 3.16, 4.19, 5.10, 6.6 (默认使用该架构的默认版本)
#
# 示例:
#   ./build.sh x86_64           # x86_64 + Linux 3.16 (默认)
#   ./build.sh x86_64 6.6       # x86_64 + Linux 6.6
#   ./build.sh aarch64          # AArch64 + Linux 6.6 (默认)
#   ./build.sh aarch64 4.19     # AArch64 + Linux 4.19
#   ./build.sh list             # 列出所有可用配置
#   ./build.sh qemu aarch64     # 查看 QEMU 运行命令

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILDROOT_DIR="${PROJECT_DIR}/buildroot"
BR_EXTERNAL="${PROJECT_DIR}/br_external"
JOBS=$(nproc)

# 架构列表
ALL_ARCHS=(x86_64 arm aarch64 riscv64)

# 架构 → 默认内核版本
declare -A ARCH_DEFAULT_VER
ARCH_DEFAULT_VER["x86_64"]="3.16"
ARCH_DEFAULT_VER["arm"]="6.6"
ARCH_DEFAULT_VER["aarch64"]="6.6"
ARCH_DEFAULT_VER["riscv64"]="6.6"

# Patch fakeroot wrapper: 在 LD_LIBRARY_PATH 中插入系统库路径，
# 防止 Buildroot host/lib 下的 libncursesw.so 与系统 libreadline.so 冲突。
# Buildroot 的 fakeroot 脚本设置 LD_LIBRARY_PATH 时优先指向 host/lib，
# 导致系统 bash/readline 加载了 host 构建的 libncursesw（版本不匹配）。
patch_fakeroot_libpath() {
    local output_dir="$1"
    local fakeroot_script="${output_dir}/host/bin/fakeroot"
    local sys_lib_dir="/usr/lib"
    if [ -f "$fakeroot_script" ]; then
        # 在 PATHS 开头插入 /usr/lib（如果还没插入过）
        if grep -q "^PATHS=${sys_lib_dir}:" "$fakeroot_script" 2>/dev/null; then
            return 0
        fi
        sed -i "s|^PATHS=\(.\+\)|PATHS=${sys_lib_dir}:\1|" "$fakeroot_script"
        echo "     已 patch fakeroot LD_LIBRARY_PATH: ${sys_lib_dir} 优先"
    fi
}

# (架构, 内核版本) → defconfig 映射
defconfig_name() {
    local arch="$1"
    local ver="$2"
    local tag="${ver%%-*}"  # "5.10-219" → "5.10", 取前段用作 major
    local major="${tag%%.*}"
    # 版本号带横线时用 "5-219" 形式作为 defconfig 名后缀
    case "$ver" in
        *-*) local sub="${ver#*-}"
             case "$arch" in
                 x86_64)  echo "linux${major}-${sub}_x86_64_defconfig" ;;
                 arm)     echo "linux${major}-${sub}_arm_vexpress_defconfig" ;;
                 aarch64) echo "linux${major}-${sub}_aarch64_virt_defconfig" ;;
                 riscv64) echo "linux${major}-${sub}_riscv64_virt_defconfig" ;;
             esac ;;
        *)   case "$arch" in
                 x86_64)  echo "linux${major}_x86_64_defconfig" ;;
                 arm)     echo "linux${major}_arm_vexpress_defconfig" ;;
                 aarch64) echo "linux${major}_aarch64_virt_defconfig" ;;
                 riscv64) echo "linux${major}_riscv64_virt_defconfig" ;;
             esac ;;
    esac
}

# 架构 → 支持的内核版本列表
supported_versions() {
    local arch="$1"
    case "$arch" in
        x86_64)  echo "3.16 4.19 5.10 5.10-219 6.6" ;;
        arm)     echo "3.16 4.19 5.10 6.6" ;;
        aarch64) echo "4.19 5.10 6.6" ;;
        riscv64) echo "5.10 6.6" ;;
    esac
}

# 验证 (架构, 内核版本) 合法性
validate_version() {
    local arch="$1"
    local ver="$2"
    for v in $(supported_versions "$arch"); do
        if [ "$v" = "$ver" ]; then
            return 0
        fi
    done
    return 1
}

# 完整内核版本号
kernel_full_version() {
    local ver="$1"
    case "$ver" in
        3.16) echo "3.16.85" ;;
        4.19) echo "4.19.325" ;;
        5.10)     echo "5.10.235" ;;
        5.10-219) echo "5.10.219" ;;
        5.15) echo "5.15.179" ;;
        6.1)  echo "6.1.130" ;;
        6.6)  echo "6.6.99"  ;;
        6.12) echo "6.12.20" ;;
        *)    echo "$ver" ;;
    esac
}

# QEMU 运行命令
# 可通过环境变量配置:
#   QEMU_PORTS=2222:22,8080:80    端口映射（逗号分隔，宿主机:虚拟机）
#   QEMU_DISK=/path/to/disk.img   磁盘镜像路径
#   QEMU_MEM=1G                   内存大小（默认 512M）
# 也可直接在命令行指定端口映射:
#   ./build.sh qemu x86_64 5.10 5555:22,8080:80
run_qemu() {
    local arch="$1"
    local kernel_ver="${2:-$(arch_default_version "$arch")}"
    local output_dir="${PROJECT_DIR}/${arch}-${kernel_ver}"
    local images="${output_dir}/images"

    # 检查第三个参数是否为端口映射（格式: 数字:数字 或 数字:数字,数字:数字）
    local ports_arg=""
    if [[ -n "${3:-}" && "$3" =~ ^[0-9]+:[0-9]+(,[0-9]+:[0-9]+)*$ ]]; then
        ports_arg="$3"
        shift 3
    else
        shift 2
    fi

    # 端口映射优先级: 命令行参数 > QEMU_PORTS 环境变量 > 默认 2222:22
    local ports="${ports_arg:-${QEMU_PORTS:-2222:22}}"
    IFS=',' read -ra port_mappings <<< "$ports"

    local disk="${QEMU_DISK:-${images}/disk.img}"
    local mem="${QEMU_MEM:-512M}"

    # 构建端口映射标志: hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80
    local netdev_args="user,id=net0"
    for pm in "${port_mappings[@]}"; do
        netdev_args="${netdev_args},hostfwd=tcp::${pm/:/-:}"
    done

    case "$arch" in
        x86_64)
            # 构建旧式 -net 参数（用 -net user 替换 -netdev）
            local net_user_args="user"
            for pm in "${port_mappings[@]}"; do
                net_user_args="${net_user_args},hostfwd=tcp::${pm/:/-:}"
            done
            # 使用相对路径（相对于项目根目录），对齐用户手写格式
            local rel_dir="${arch}-${kernel_ver}/images"
            set -- qemu-system-x86_64 \
                -m "${mem}" \
                -kernel "${rel_dir}/bzImage" \
                -hda "${rel_dir}/rootfs.ext4" \
                -append "root=/dev/sda console=ttyS0 nokaslr" \
                -nographic -smp 4 -enable-kvm \
                -net "${net_user_args}" \
                -net nic \
                "$@"
            ;;
        arm)
            set -- qemu-system-arm -M vexpress-a9 \
                -m "${mem}" \
                -kernel "${images}/zImage" \
                -dtb "${images}/vexpress-v2p-ca9.dtb" \
                -drive "file=${images}/rootfs.ext4,if=sd,format=raw" \
                -append "console=ttyAMA0 root=/dev/mmcblk0" \
                -netdev "${netdev_args}" \
                -device virtio-net-device,netdev=net0 \
                -nographic \
                "$@"
            ;;
        aarch64)
            set -- qemu-system-aarch64 -M virt -cpu cortex-a53 \
                -m "${mem}" \
                -kernel "${images}/Image" \
                -drive "file=${images}/rootfs.ext4,if=none,format=raw,id=hd0" \
                -device virtio-blk-device,drive=hd0 \
                -append "console=ttyAMA0 root=/dev/vda" \
                -netdev "${netdev_args}" \
                -device virtio-net-device,netdev=net0 \
                -nographic \
                "$@"
            ;;
        riscv64)
            set -- qemu-system-riscv64 -M virt \
                -m "${mem}" \
                -kernel "${images}/Image" \
                -drive "file=${images}/rootfs.ext4,if=none,format=raw,id=hd0" \
                -device virtio-blk-device,drive=hd0 \
                -append "console=ttyS0 root=/dev/vda" \
                -netdev "${netdev_args}" \
                -device virtio-net-device,netdev=net0 \
                -nographic \
                "$@"
            ;;
    esac

    # 格式化展示走 stderr（始终显示），单行命令走 stdout（仅 eval 时捕获）
    local cmd_flat="" cmd_pretty="" indent="    " nl=$'\n'
    local first=true
    for arg in "$@"; do
        # 参数含空格时加引号，便于复制粘贴
        if [[ "$arg" == *" "* ]]; then
            arg="\"$arg\""
        fi
        if $first; then
            cmd_flat="$arg"
            cmd_pretty="$arg"
            first=false
        else
            cmd_flat="${cmd_flat} ${arg}"
            if [[ "$arg" == -* ]] || [[ "$arg" == \"-*\" ]]; then
                cmd_pretty="${cmd_pretty} \\${nl}${indent}${arg}"
            else
                cmd_pretty="${cmd_pretty} ${arg}"
            fi
        fi
    done
    # stdout: 仅在被捕获（eval 场景）时输出单行命令
    if [ ! -t 1 ]; then
        printf "%s\n" "$cmd_flat"
    fi
    # stderr: 格式化展示（终端交互时也可见）
    echo "运行命令:" >&2
    echo "  $cmd_pretty" >&2
    echo "" >&2
    echo "复制粘贴上述命令启动，或直接运行:" >&2
    echo "  eval \$($0 qemu $arch $kernel_ver)" >&2
}

arch_default_version() {
    echo "${ARCH_DEFAULT_VER[$1]}"
}

list_configs() {
    echo "可用配置："
    echo ""
    printf "  %-10s %-30s %-15s %s\n" "架构" "Defconfig" "输出目录" "支持的内核版本"
    printf "  %-10s %-30s %-15s %s\n" "--------" "------------------------------" "---------------" "------------------------"
    for arch in "${ALL_ARCHS[@]}"; do
        local default_ver
        default_ver=$(arch_default_version "$arch")
        local versions
        versions=$(supported_versions "$arch" | tr ' ' ',')
        local defcfg
        defcfg=$(defconfig_name "$arch" "$default_ver")
        local outdir="${arch}-${default_ver}"
        printf "  %-10s %-30s %-15s %s\n" \
            "$arch" "$defcfg" "$outdir" "$versions"
    done
    echo ""
    echo "构建:  ./build.sh <架构> [内核版本]"
    echo "示例:  ./build.sh x86_64           # 默认 Linux 3.16"
    echo "       ./build.sh x86_64 6.6       # 指定 Linux 6.6"
    echo "       ./build.sh aarch64 4.19     # AArch64 + Linux 4.19"
    echo "运行:  ./build.sh qemu <架构> [内核版本]"
    echo ""
}

# --- 参数解析 ---
case "${1:-}" in
    list|ls|--help|-h)
        list_configs
        exit 0
        ;;
    qemu|run)
        if [ -z "${2:-}" ]; then
            echo "用法: ./build.sh qemu <架构> [内核版本] [额外 QEMU 参数...]"
            exit 1
        fi
        run_qemu "$2" "${3:-}" "${@:4}"
        exit 0
        ;;
    "")
        echo "用法: ./build.sh <架构> [内核版本]"
        echo "运行 './build.sh list' 查看所有配置"
        exit 1
        ;;
esac

ARCH="$1"
KERNEL_VER="${2:-$(arch_default_version "$ARCH")}"

# 验证架构
if [ -z "${ARCH_DEFAULT_VER[$ARCH]:-}" ]; then
    echo "错误: 不支持的架构 '$ARCH'"
    echo "支持的架构: ${ALL_ARCHS[*]}"
    exit 1
fi

# 验证内核版本
if ! validate_version "$ARCH" "$KERNEL_VER"; then
    echo "错误: 架构 '$ARCH' 不支持内核版本 '$KERNEL_VER'"
    echo "支持的版本: $(supported_versions "$ARCH")"
    exit 1
fi

DEFCONFIG=$(defconfig_name "$ARCH" "$KERNEL_VER")
OUTPUT_DIR="${PROJECT_DIR}/${ARCH}-${KERNEL_VER}"
KERNEL_FULL=$(kernel_full_version "$KERNEL_VER")

echo "=================================="
echo " Linux3 Build System"
echo "=================================="
echo "  架构:      $ARCH"
echo "  内核版本:  Linux ${KERNEL_FULL}"
echo "  Defconfig: $DEFCONFIG"
echo "  输出目录:  $OUTPUT_DIR"
echo "  CPU 核心:  $JOBS"
echo "=================================="

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 1. 配置
echo ""
echo "[1/2] 配置..."
cd "$BUILDROOT_DIR"
make BR2_EXTERNAL="$BR_EXTERNAL" \
     O="$OUTPUT_DIR" \
     "${DEFCONFIG}"

# Patch fakeroot（如果有之前构建的残留）
patch_fakeroot_libpath "$OUTPUT_DIR"

# 2. 构建
echo ""
echo "[2/2] 构建中..."
echo "     日志: ${OUTPUT_DIR}/build.log"
echo ""

make BR2_EXTERNAL="$BR_EXTERNAL" \
     O="$OUTPUT_DIR" \
     -j"$JOBS" 2>&1 | tee "${OUTPUT_DIR}/build.log"
BUILD_STATUS=$?

# Patch fakeroot（确保新构建的也被修复）
patch_fakeroot_libpath "$OUTPUT_DIR"

echo ""
if [ $BUILD_STATUS -eq 0 ]; then
    echo "构建成功!"
    echo "  镜像位置: ${OUTPUT_DIR}/images/"
    echo ""
    echo "运行 QEMU:"
    echo "  $0 qemu $ARCH $KERNEL_VER"
    echo ""
    run_qemu "$ARCH" "$KERNEL_VER" >/dev/null 2>&1 || true
else
    echo "构建失败 (退出码: $BUILD_STATUS)"
    echo "  查看日志: tail -100 ${OUTPUT_DIR}/build.log"
fi

exit $BUILD_STATUS
