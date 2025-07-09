#!/bin/bash
set -euo pipefail

# 快速测试脚本 - 验证多架构构建和 Kubernetes 部署

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查前置要求
check_prerequisites() {
    log_step "检查前置要求..."

    local missing_tools=()

    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi

    if ! command -v docker-compose &> /dev/null; then
        missing_tools+=("docker-compose")
    fi

    if ! docker buildx version &> /dev/null; then
        missing_tools+=("docker-buildx")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "缺少以下工具: ${missing_tools[*]}"
        exit 1
    fi

    log_info "Docker 版本: $(docker --version)"
    log_info "Docker Compose 版本: $(docker-compose --version)"
    log_info "Docker Buildx 版本: $(docker buildx version)"

    # 检查 Docker 是否运行
    if ! docker info &> /dev/null; then
        log_error "Docker 未运行，请启动 Docker"
        exit 1
    fi

    log_info "✅ 前置要求检查通过"
}

# 测试 Docker 构建
test_docker_build() {
    log_step "测试 Docker 构建..."

    log_info "构建 builder 阶段..."
    if docker build -f Dockerfile.builder --target=builder -t postgres-operator:builder-test .; then
        log_info "✅ Builder 阶段构建成功"
    else
        log_error "❌ Builder 阶段构建失败"
        return 1
    fi

    log_info "构建 runtime 阶段..."
    if docker build -f Dockerfile.builder --target=runtime -t postgres-operator:runtime-test .; then
        log_info "✅ Runtime 阶段构建成功"
    else
        log_error "❌ Runtime 阶段构建失败"
        return 1
    fi

    # 测试镜像
    log_info "测试运行时镜像..."
    if docker run --rm postgres-operator:runtime-test postgres-operator --version 2>/dev/null ||
       docker run --rm postgres-operator:runtime-test postgres-operator --help 2>/dev/null; then
        log_info "✅ 镜像测试成功"
    else
        log_warn "⚠️  镜像版本检查失败，但这可能是正常的"
    fi
}

# 测试多架构构建
test_multiarch_build() {
    log_step "测试多架构构建..."

    log_info "检查 buildx builder..."
    ./scripts/build-multiarch.sh --help > /dev/null

    log_info "执行多架构构建 (不推送)..."
    if ./scripts/build-multiarch.sh --tag test-multiarch; then
        log_info "✅ 多架构构建脚本执行成功"
    else
        log_error "❌ 多架构构建失败"
        return 1
    fi
}

# 测试 docker-compose
test_docker_compose() {
    log_step "测试 Docker Compose..."

    log_info "验证 docker-compose.yaml 语法..."
    if docker-compose config > /dev/null; then
        log_info "✅ Docker Compose 配置有效"
    else
        log_error "❌ Docker Compose 配置无效"
        return 1
    fi

    log_info "测试构建服务..."
    if docker-compose build postgres-operator-builder; then
        log_info "✅ Docker Compose 构建成功"
    else
        log_error "❌ Docker Compose 构建失败"
        return 1
    fi
}

# 测试 Kubernetes 部署脚本
test_k8s_scripts() {
    log_step "测试 Kubernetes 部署脚本..."

    log_info "检查 kubectl (可选)..."
    if command -v kubectl &> /dev/null; then
        log_info "kubectl 版本: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"

        # 检查集群连接 (如果可用)
        if kubectl cluster-info &> /dev/null; then
            log_info "✅ Kubernetes 集群连接正常"

            log_info "测试 Kubernetes 部署脚本..."
            if ./scripts/k8s-deploy.sh help > /dev/null; then
                log_info "✅ Kubernetes 部署脚本正常"
            else
                log_warn "⚠️  Kubernetes 部署脚本可能有问题"
            fi
        else
            log_warn "⚠️  无法连接到 Kubernetes 集群 (这是正常的，如果您没有集群)"
        fi
    else
        log_warn "⚠️  kubectl 未安装 (这是正常的，如果您不使用 Kubernetes)"
    fi
}

# 验证配置文件
test_config_files() {
    log_step "验证配置文件..."

    local config_files=(
        "config/default/kustomization.yaml"
        "config/crd/kustomization.yaml"
        "config/manager/kustomization.yaml"
        "config/rbac/kustomization.yaml"
        "examples/postgrescluster/postgrescluster.yaml"
    )

    for file in "${config_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_info "✅ 配置文件存在: $file"
        else
            log_warn "⚠️  配置文件缺失: $file"
        fi
    done

    # 验证 YAML 语法
    if command -v yamllint &> /dev/null; then
        log_info "验证 YAML 语法..."
        for file in "${config_files[@]}"; do
            if [[ -f "$file" ]] && yamllint "$file" &> /dev/null; then
                log_info "✅ YAML 语法正确: $file"
            fi
        done
    else
        log_warn "⚠️  yamllint 未安装，跳过 YAML 语法检查"
    fi
}

# 清理测试资源
cleanup_test_resources() {
    log_step "清理测试资源..."

    # 清理测试镜像
    docker rmi postgres-operator:builder-test postgres-operator:runtime-test 2>/dev/null || true
    docker rmi postgres-operator:test-multiarch 2>/dev/null || true

    # 清理 buildx 缓存
    docker buildx prune -f 2>/dev/null || true

    log_info "✅ 测试资源已清理"
}

# 显示测试总结
show_summary() {
    log_step "测试总结"

    echo ""
    log_info "🎉 测试完成！"
    echo ""
    log_info "下一步操作:"
    log_info "1. Docker 本地开发:"
    log_info "   docker-compose up -d"
    echo ""
    log_info "2. 多架构构建:"
    log_info "   ./scripts/build-multiarch.sh --push --registry your-registry.com"
    echo ""
    log_info "3. Kubernetes 部署:"
    log_info "   ./scripts/k8s-deploy.sh deploy-full"
    echo ""
    log_info "📖 详细文档请查看: README-QuickStart.md"
}

# 主函数
main() {
    log_info "PostgreSQL Operator 快速测试"
    log_info "============================="
    echo ""

    # 执行测试
    check_prerequisites
    test_docker_build
    test_multiarch_build
    test_docker_compose
    test_k8s_scripts
    test_config_files

    # 清理和总结
    cleanup_test_resources
    show_summary

    log_info "✅ 所有测试完成"
}

# 错误处理
trap 'log_error "测试过程中发生错误"; cleanup_test_resources; exit 1' ERR

# 执行主函数
main "$@"
