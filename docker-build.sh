#!/usr/bin/env bash
set -e

# 镜像名
IMAGE="fnproject/fnserver"
TAG="${TAG:-latest}"
# 导出目录
DIST_DIR="${DIST_DIR:-dist}"

# 解析参数: ./docker-build.sh [命令] [架构]
# 命令: build(默认) / export / push
# 架构: 默认根据当前机器架构
detect_current_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *)
      echo "无法识别当前架构: $(uname -m), 请显式指定 amd64 或 arm64" >&2
      exit 1
      ;;
  esac
}

usage() {
  echo "用法: $0 [命令] [架构]"
  echo "命令:"
  echo "  build   构建镜像并导入本地 docker (默认)"
  echo "  export  构建镜像并导出 gzip 压缩包到 ${DIST_DIR}/"
  echo "  push    构建镜像并推送到镜像仓库"
  echo "架构:"
  echo "  amd64|x86: 仅构建 x86_64 镜像"
  echo "  arm64|arm: 仅构建 arm64 镜像"
  echo "  all: 同时构建两种架构"
  echo "  不传参数: 根据当前机器架构构建 (默认)"
  echo "环境变量:"
  echo "  TAG=<tag>       镜像标签 (默认 latest)"
  echo "  DIST_DIR=<dir>  导出目录 (默认 dist)"
  echo "示例:"
  echo "  $0                        # 构建当前架构"
  echo "  $0 export arm64           # 构建 arm64 并导出压缩包"
  echo "  $0 export all             # 构建双架构并分别导出压缩包"
  echo "  $0 push                   # 推送当前架构镜像"
}

# ---------- 解析命令 ----------
CMD="build"
if [ $# -ge 1 ]; then
  case "$1" in
    build|export|push) CMD="$1"; shift ;;
    -h|--help)         usage; exit 0 ;;
  esac
fi

# ---------- 解析架构 ----------
PLATFORM_ARG="${1:-$(detect_current_arch)}"
[ "$1" = "all" ] && shift

case "$PLATFORM_ARG" in
  amd64|x86)  PLATFORMS="linux/amd64" ;;
  arm64|arm)  PLATFORMS="linux/arm64" ;;
  all)        PLATFORMS="linux/amd64,linux/arm64" ;;
  *)
    usage
    exit 1
    ;;
esac

# 确保 buildx 构建器存在并启用
if ! docker buildx ls | grep -q "fnbuilder"; then
  echo "创建多架构构建器 fnbuilder ..."
  docker buildx create --name fnbuilder --use
fi
docker buildx use fnbuilder

# ---------- 导出镜像: docker save + gzip 压缩 ----------
# 文件名规范: fnserver_<os>_<arch>_<tag>.tar.gz, 如 fnserver_linux_amd64_latest.tar.gz
export_image() {
  local platform="$1" arch="${1##*/}"
  local out_file="${DIST_DIR}/fnserver_linux_${arch}_${TAG}.tar.gz"

  echo ">>> 导出 ${IMAGE}:${TAG}-${arch} -> ${out_file}"
  mkdir -p "${DIST_DIR}"
  docker save "${IMAGE}:${TAG}-${arch}" | gzip -6 > "${out_file}"
  echo "    完成: $(du -h "${out_file}" | cut -f1) ${out_file}"
}

# ---------- 按命令执行 ----------
case "$CMD" in
  push)
    # 推送: 多架构合并为单一 manifest, 单架构直接推送
    echo "构建并推送: ${IMAGE}:${TAG} [${PLATFORMS}]"
    docker buildx build --platform "${PLATFORMS}" -t "${IMAGE}:${TAG}" --push .
    ;;

  export)
    # 导出: 逐架构构建(本地 load)并导出压缩包
    for PLATFORM in $(echo "$PLATFORMS" | tr ',' ' '); do
      ARCH="${PLATFORM##*/}"
      echo ">>> 构建 ${IMAGE}:${TAG}-${ARCH} [${PLATFORM}]"
      docker buildx build --platform "${PLATFORM}" \
        -t "${IMAGE}:${TAG}-${ARCH}" --load .
      export_image "${PLATFORM}"
    done
    ;;

  build)
    if [ "${PLATFORMS}" = "linux/amd64,linux/arm64" ]; then
      # 本地 load 不支持多架构单标签, 按架构分别构建并打上架构后缀标签
      for PLATFORM in $(echo "$PLATFORMS" | tr ',' ' '); do
        ARCH="${PLATFORM##*/}"
        echo ">>> 构建 ${IMAGE}:${TAG}-${ARCH}"
        docker buildx build --platform "${PLATFORM}" \
          -t "${IMAGE}:${TAG}-${ARCH}" --load .
      done
    else
      # 单架构, 标签不带架构后缀
      echo "构建: ${IMAGE}:${TAG} [${PLATFORMS}]"
      docker buildx build --platform "${PLATFORMS}" -t "${IMAGE}:${TAG}" --load .
    fi
    ;;
esac
