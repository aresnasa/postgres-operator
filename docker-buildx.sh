#!/bin/bash

# PostgreSQL Operator 多架构 Docker 构建脚本
# 支持 AMD64 和 ARM64 架构

set -e

# 配置变量
IMAGE_NAME="postgres-operator"
TAG="${TAG:-latest}"
REGISTRY="${REGISTRY:-}"
BUILDER_NAME="postgres-operator-builder"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 Docker 和 buildx
check_prerequisites() {
    log_info "检查构建环境..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        exit 1
    fi

    if ! docker buildx version &> /dev/null; then
        log_error "Docker Buildx 未安装或未启用"
        exit 1
    fi

    log_success "构建环境检查通过"
}

# 创建或使用 buildx builder
setup_builder() {
    log_info "设置多架构构建器..."

    # 检查是否已存在构建器
    if docker buildx inspect $BUILDER_NAME &> /dev/null; then
        log_info "构建器 $BUILDER_NAME 已存在，使用现有构建器"
        docker buildx use $BUILDER_NAME
    else
        log_info "创建新的构建器 $BUILDER_NAME"
        docker buildx create --name $BUILDER_NAME --driver docker-container --bootstrap
        docker buildx use $BUILDER_NAME
    fi

    # 启动构建器（如果未运行）
    docker buildx inspect --bootstrap

    log_success "构建器设置完成"
}

# 构建多架构镜像
build_multiarch() {
    local push_flag=""
    local load_flag=""
    local full_image_name="${IMAGE_NAME}:${TAG}"

    if [ -n "$REGISTRY" ]; then
        full_image_name="${REGISTRY}/${full_image_name}"
        push_flag="--push"
        log_info "将推送到注册表: $REGISTRY"
    else
        # 本地构建时不能同时支持多架构，选择构建单架构并加载到本地
        log_warn "本地构建模式：将只构建当前平台架构并加载到本地"
        local current_arch=$(docker version --format '{{.Server.Arch}}')
        log_info "当前平台架构: $current_arch"

        docker buildx build \
            --file Dockerfile.builder \
            --platform linux/$current_arch \
            --tag $full_image_name \
            --load \
            .

        log_success "单架构镜像构建完成: $full_image_name"
        return 0
    fi

    log_info "开始构建多架构镜像..."
    log_info "目标平台: linux/amd64, linux/arm64"
    log_info "镜像标签: $full_image_name"

    # 构建多架构镜像
    docker buildx build \
        --file Dockerfile.builder \
        --platform linux/amd64,linux/arm64 \
        --tag $full_image_name \
        $push_flag \
        --progress=plain \
        .

    log_success "多架构镜像构建完成: $full_image_name"
}

# 清理构建器
cleanup_builder() {
    if [ "$1" = "--cleanup" ]; then
        log_info "清理构建器..."
        docker buildx rm $BUILDER_NAME || true
        log_success "构建器清理完成"
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
PostgreSQL Operator 多架构 Docker 构建脚本

用法:
    $0 [选项]

选项:
    --tag TAG           设置镜像标签 (默认: latest)
    --registry URL      设置镜像注册表 (用于推送)
    --cleanup          构建完成后清理构建器
    --help             显示此帮助信息

环境变量:
    TAG                镜像标签
    REGISTRY           镜像注册表

示例:
    # 本地构建 (单架构)
    $0

    # 指定标签构建
    $0 --tag v1.0.0

    # 构建并推送到注册表
    $0 --registry docker.io/myorg --tag v1.0.0

    # 使用环境变量
    TAG=v1.0.0 REGISTRY=docker.io/myorg $0

    # 构建完成后清理
    $0 --cleanup

EOF
}

# 解析命令行参数
CLEANUP=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)
            TAG="$2"
            shift 2
            ;;
        --registry)
            REGISTRY="$2"
            shift 2
            ;;
        --cleanup)
            CLEANUP=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 主执行流程
main() {
    log_info "开始 PostgreSQL Operator 多架构构建"
    log_info "镜像标签: $TAG"

    check_prerequisites
    setup_builder
    build_multiarch

    if [ "$CLEANUP" = true ]; then
        cleanup_builder --cleanup
    fi

    log_success "构建完成！"

    # 显示构建结果
    if [ -n "$REGISTRY" ]; then
        log_info "镜像已推送到: ${REGISTRY}/${IMAGE_NAME}:${TAG}"
    else
        log_info "本地镜像: ${IMAGE_NAME}:${TAG}"
        log_info "查看镜像: docker images ${IMAGE_NAME}"
    fi
}

# 错误处理
trap 'log_error "构建过程中发生错误，退出码: $?"' ERR

# 执行主函数
main
