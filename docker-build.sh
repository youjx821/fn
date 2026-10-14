#!/bin/bash

# ==============================================================================
# fn (Fn Server) Docker 镜像构建脚本
# 支持构建 x86(amd64) 与 arm(arm64) 架构镜像
# 默认根据当前机器架构构建，支持镜像导出 (.tar.gz)
# 保持与 fn-java-docker-base / fn-python-docker-base-311 规范一致
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_REPO="${IMAGE:-fnproject/fnserver}"
DEFAULT_TAG="latest"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_usage() {
    echo "用法: $0 [选项] [架构]"
    echo ""
    echo "架构参数 (可选):"
    echo "  x86 | amd64 | x86_64      构建 x86_64 (linux/amd64) 镜像"
    echo "  arm | arm64 | aarch64     构建 arm64 (linux/arm64) 镜像"
    echo "  all                       依次构建 x86 与 arm 两个架构的镜像"
    echo "  (默认: 自动检测当前主机架构)"
    echo ""
    echo "选项:"
    echo "  -a, --arch <架构>          指定目标架构 (x86|arm|all)"
    echo "  -e, --export              构建后导出镜像为 .tar.gz 压缩包"
    echo "  -o, --output <路径>        导出文件路径或目录 (指定此项自动开启导出)"
    echo "  -t, --tag <标签>           镜像标签 (默认: $DEFAULT_TAG)"
    echo "  -p, --push                构建后推送到镜像仓库"
    echo "  -h, --help                显示帮助信息"
    echo ""
    echo "兼容旧版命令格式:"
    echo "  $0 build [架构]           构建镜像并导入本地 docker (默认)"
    echo "  $0 export [架构]          构建镜像并导出压缩包"
    echo "  $0 push [架构]            构建镜像并推送到镜像仓库"
    echo ""
    echo "示例:"
    echo "  $0                        # 按当前架构构建"
    echo "  $0 --export               # 按当前架构构建并导出"
    echo "  $0 -a arm64 -e            # 构建 arm64 镜像并导出"
    echo "  $0 all -e                 # 构建 x86 和 arm 镜像并全部导出"
    echo "  $0 -a x86 -o ./images/    # 构建 x86 镜像并导出到指定目录"
    echo "  $0 -a x86 -o ../aip-mcphelper/mcp-fn-server/images/ # 导出到 MCP-FN-Server 镜像目录"
}

# 检测当前机器架构
detect_host_arch() {
    local machine=$(uname -m)
    case "$machine" in
        x86_64|amd64|i386|i686)
            echo "x86_64"
            ;;
        aarch64|arm64|armv8*|armv7*)
            echo "arm64"
            ;;
        *)
            echo "x86_64"
            ;;
    esac
}

# 规范化架构名称
normalize_arch() {
    local input=$1
    case "$input" in
        x86|x86_64|amd64)
            echo "x86_64"
            ;;
        arm|arm64|aarch64)
            echo "arm64"
            ;;
        all)
            echo "all"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# 获取 Docker 平台标识
get_docker_platform() {
    local arch=$1
    case "$arch" in
        x86_64)
            echo "linux/amd64"
            ;;
        arm64)
            echo "linux/arm64"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 参数解析
TARGET_ARCH=""
DO_EXPORT=false
DO_PUSH=false
OUTPUT_PATH=""
IMAGE_TAG="${TAG:-$DEFAULT_TAG}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--arch)
            TARGET_ARCH="$2"
            shift 2
            ;;
        -e|--export)
            DO_EXPORT=true
            shift
            ;;
        -o|--output)
            DO_EXPORT=true
            OUTPUT_PATH="$2"
            shift 2
            ;;
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -p|--push)
            DO_PUSH=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        build)
            shift
            ;;
        export)
            DO_EXPORT=true
            shift
            ;;
        push)
            DO_PUSH=true
            shift
            ;;
        x86|amd64|x86_64|arm|arm64|aarch64|all)
            TARGET_ARCH="$1"
            shift
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            print_usage
            exit 1
            ;;
    esac
done

# 如果未指定架构，默认使用当前主机架构
if [ -z "$TARGET_ARCH" ]; then
    TARGET_ARCH=$(detect_host_arch)
    echo -e "${BLUE}[INFO]${NC} 未指定架构，自动检测当前主机架构: ${TARGET_ARCH}"
fi

TARGET_ARCH=$(normalize_arch "$TARGET_ARCH")
if [ "$TARGET_ARCH" = "unknown" ]; then
    echo -e "${RED}[ERROR] 不支持的目标架构: $TARGET_ARCH${NC}"
    exit 1
fi

# 检查 Docker 环境
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] 未检测到 Docker，请先安装 Docker。${NC}"
    exit 1
fi

# 单架构构建与导出逻辑
build_single_arch() {
    local arch=$1
    local platform=$(get_docker_platform "$arch")
    local full_image="${IMAGE_REPO}:${IMAGE_TAG}"

    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}开始构建镜像: ${full_image} (${arch} / ${platform})${NC}"
    echo -e "${GREEN}=========================================${NC}"

    local build_cmd="docker build"
    if docker buildx version >/dev/null 2>&1; then
        build_cmd="docker buildx build --load"
    fi

    if [ "$DO_PUSH" = true ]; then
        echo -e "${BLUE}[INFO]${NC} 正在构建并推送到仓库..."
        docker buildx build --platform "$platform" -t "$full_image" --push "$SCRIPT_DIR"
        echo -e "${GREEN}✓ 镜像推送完成: ${full_image} (${platform})${NC}"
    else
        $build_cmd --platform "$platform" -t "$full_image" "$SCRIPT_DIR"
        echo -e "${GREEN}✓ 镜像构建完成: ${full_image} (${platform})${NC}"
    fi

    if [ "$DO_EXPORT" = true ]; then
        local target_file=""
        local default_filename="fnproject_fnserver_${IMAGE_TAG}_${arch}.tar.gz"

        if [ -z "$OUTPUT_PATH" ]; then
            target_file="$SCRIPT_DIR/$default_filename"
        elif [ -d "$OUTPUT_PATH" ] || [[ "$OUTPUT_PATH" == */ ]]; then
            mkdir -p "$OUTPUT_PATH"
            target_file="${OUTPUT_PATH%/}/$default_filename"
        else
            target_file="$OUTPUT_PATH"
            mkdir -p "$(dirname "$target_file")"
        fi

        echo ""
        echo -e "${BLUE}[INFO]${NC} 正在导出镜像到: $target_file ..."
        docker save "$full_image" | gzip -1 > "$target_file"

        local file_size=$(du -h "$target_file" 2>/dev/null | cut -f1 || ls -lh "$target_file" | awk '{print $5}')
        echo -e "${GREEN}✓ 镜像导出成功: $target_file (大小: $file_size)${NC}"
    fi
}

# 执行构建
if [ "$TARGET_ARCH" = "all" ]; then
    build_single_arch "x86_64"
    build_single_arch "arm64"
else
    build_single_arch "$TARGET_ARCH"
fi

echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}✓ fnserver 构建处理完毕!${NC}"
echo -e "${GREEN}=========================================${NC}"