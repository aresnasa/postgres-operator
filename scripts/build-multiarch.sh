#!/bin/bash
set -euo pipefail

# PostgreSQL Operator 多架构构建脚本
# 支持 ARM64 和 AMD64 架构

# 配置变量
IMAGE_NAME=${PGO_IMAGE_NAME:-"postgres-operator"}
IMAGE_TAG=${PGO_IMAGE_TAG:-"latest"}
IMAGE_REGISTRY=${PGO_IMAGE_REGISTRY:-"localhost"}
DOCKERFILE=${DOCKERFILE:-"Dockerfile.builder"}

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 Docker Buildx
check_buildx() {
    log_info "检查 Docker Buildx 支持..."
    if ! docker buildx version > /dev/null 2>&1; then
        log_error "Docker Buildx 未安装或不可用"
        log_info "请安装 Docker Desktop 或手动安装 buildx 插件"
        exit 1
    fi

    # 如果需要重建 builder
    if [[ "${REBUILD_BUILDER:-false}" == "true" ]]; then
        log_info "重建 multiarch-builder..."
        docker buildx rm multiarch-builder 2>/dev/null || true
        docker buildx create --name multiarch-builder --driver docker-container --use
        docker buildx inspect --bootstrap
        return
    fi

    # 检查并设置 buildx builder
    if docker buildx ls | grep -q "multiarch-builder"; then
        log_info "使用现有的 multiarch-builder..."
        docker buildx use multiarch-builder

        # 确保 builder 正常工作
        if ! docker buildx inspect 2>/dev/null | grep -q "running"; then
            log_info "启动 multiarch-builder..."
            docker buildx inspect --bootstrap
        fi
    else
        log_info "创建多架构 builder..."
        docker buildx create --name multiarch-builder --driver docker-container --use
        docker buildx inspect --bootstrap
    fi

    # 验证 builder 支持多架构
    if ! docker buildx inspect | grep -q "linux/arm64\|linux/amd64"; then
        log_warn "Builder 可能不支持所需的架构，但继续尝试..."
    fi
}

# 构建多架构镜像
build_multiarch() {
    local push_flag=""
    if [[ "${PUSH_TO_REGISTRY:-false}" == "true" ]]; then
        push_flag="--push"
        log_info "将推送镜像到注册表: ${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    else
        push_flag="--load"
        log_warn "镜像将仅构建到本地 (不推送到注册表)"
        log_warn "多架构镜像需要推送到注册表才能在 Kubernetes 中使用"
    fi

    log_info "开始构建多架构镜像..."
    log_info "镜像名称: ${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    log_info "支持架构: linux/amd64, linux/arm64"

    docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --file "${DOCKERFILE}" \
        --target runtime \
        --tag "${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}" \
        --tag "${IMAGE_REGISTRY}/${IMAGE_NAME}:latest" \
        ${push_flag} \
        .

    if [[ "${push_flag}" == "--load" ]]; then
        log_warn "注意: 由于 Docker 限制，--load 只会加载当前平台的镜像"
        log_info "当前平台镜像已加载: ${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    fi
}

# 验证镜像
verify_image() {
    if [[ "${PUSH_TO_REGISTRY:-false}" == "true" ]]; then
        log_info "验证推送的镜像..."
        docker buildx imagetools inspect "${IMAGE_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    else
        log_info "验证本地镜像..."
        docker images "${IMAGE_REGISTRY}/${IMAGE_NAME}"
    fi
}

# 生成 Kubernetes 部署清单
generate_k8s_manifests() {
    log_info "生成 Kubernetes 部署清单..."

    # 创建输出目录
    mkdir -p k8s-manifests

    # 更新 kustomization.yaml 中的镜像
    cat > k8s-manifests/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: postgres-operator

labels:
- includeSelectors: true
  pairs:
    postgres-operator.crunchydata.com/control-plane: postgres-operator

resources:
- ../config/crd
- ../config/rbac
- ../config/manager
- ../config/namespace

images:
- name: postgres-operator
  newName: ${IMAGE_REGISTRY}/${IMAGE_NAME}
  newTag: ${IMAGE_TAG}

EOF

    # 生成完整的部署清单
    kubectl kustomize k8s-manifests > k8s-manifests/postgres-operator-${IMAGE_TAG}.yaml

    log_info "Kubernetes 清单已生成: k8s-manifests/postgres-operator-${IMAGE_TAG}.yaml"
}

# 主函数
main() {
    log_info "PostgreSQL Operator 多架构构建脚本"
    log_info "======================================="

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            --push)
                export PUSH_TO_REGISTRY=true
                shift
                ;;
            --tag)
                export PGO_IMAGE_TAG="$2"
                shift 2
                ;;
            --registry)
                export PGO_IMAGE_REGISTRY="$2"
                shift 2
                ;;
            --name)
                export PGO_IMAGE_NAME="$2"
                shift 2
                ;;
            --dockerfile)
                export DOCKERFILE="$2"
                shift 2
                ;;
            --rebuild-builder)
                export REBUILD_BUILDER=true
                shift
                ;;
            --help|-h)
                echo "用法: $0 [选项]"
                echo "选项:"
                echo "  --push              推送镜像到注册表"
                echo "  --tag TAG           镜像标签 (默认: latest)"
                echo "  --registry REG      镜像注册表 (默认: localhost)"
                echo "  --name NAME         镜像名称 (默认: postgres-operator)"
                echo "  --dockerfile FILE   Dockerfile 路径 (默认: Dockerfile.builder)"
                echo "  --rebuild-builder   重建 buildx builder"
                echo "  --help, -h          显示此帮助信息"
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                exit 1
                ;;
        esac
    done

    # 重新设置变量（如果通过命令行参数修改了）
    IMAGE_NAME=${PGO_IMAGE_NAME:-"postgres-operator"}
    IMAGE_TAG=${PGO_IMAGE_TAG:-"latest"}
    IMAGE_REGISTRY=${PGO_IMAGE_REGISTRY:-"localhost"}
    DOCKERFILE=${DOCKERFILE:-"Dockerfile.builder"}

    log_info "构建配置:"
    log_info "  镜像名称: ${IMAGE_NAME}"
    log_info "  镜像标签: ${IMAGE_TAG}"
    log_info "  镜像注册表: ${IMAGE_REGISTRY}"
    log_info "  Dockerfile: ${DOCKERFILE}"
    log_info "  推送到注册表: ${PUSH_TO_REGISTRY:-false}"
    echo ""

    # 执行构建流程
    check_buildx
    build_multiarch
    verify_image
    generate_k8s_manifests

    log_info "构建完成！"
    log_info ""
    log_info "下一步操作:"
    if [[ "${PUSH_TO_REGISTRY:-false}" == "true" ]]; then
        log_info "1. 部署到 Kubernetes:"
        log_info "   kubectl apply -f k8s-manifests/postgres-operator-${IMAGE_TAG}.yaml"
        log_info ""
        log_info "2. 创建 PostgreSQL 集群:"
        log_info "   kubectl apply -f examples/postgrescluster/postgrescluster.yaml"
    else
        log_info "1. 推送镜像到注册表 (用于 Kubernetes 部署):"
        log_info "   $0 --push --registry YOUR_REGISTRY"
        log_info ""
        log_info "2. 或者在本地使用 docker-compose:"
        log_info "   docker-compose up -d"
    fi
}

# 执行主函数
main "$@"
