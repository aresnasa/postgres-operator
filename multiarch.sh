#!/bin/bash

# PostgreSQL Operator 多架构构建和运行脚本

set -e

# 配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# 显示帮助
show_help() {
    cat << EOF
PostgreSQL Operator 多架构构建和运行脚本

用法:
    $0 [命令] [选项]

命令:
    build       构建多架构镜像
    run         运行服务
    test        测试构建
    clean       清理镜像和容器
    help        显示帮助

选项:
    --push      推送到镜像仓库
    --no-cache  无缓存构建
    --verbose   详细输出

示例:
    $0 build                    # 本地多架构构建
    $0 build --push             # 构建并推送
    $0 run                      # 运行所有服务
    $0 test                     # 测试构建
    $0 clean                    # 清理

EOF
}

# 检查先决条件
check_prerequisites() {
    log_info "检查构建环境..."

    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        exit 1
    fi

    # 检查 Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose 未安装"
        exit 1
    fi

    # 检查 Docker Buildx
    if ! docker buildx version &> /dev/null; then
        log_error "Docker Buildx 未安装"
        exit 1
    fi

    log_success "环境检查通过"
}

# 设置 buildx
setup_buildx() {
    log_info "设置 Docker Buildx..."

    # 创建 buildx 实例（如果不存在）
    if ! docker buildx inspect postgres-operator-builder &> /dev/null; then
        docker buildx create --name postgres-operator-builder --driver docker-container --bootstrap
    fi

    # 使用 buildx 实例
    docker buildx use postgres-operator-builder

    log_success "Buildx 设置完成"
}

# 构建多架构镜像
build_multiarch() {
    local push_flag=""
    local cache_flag=""

    if [ "$PUSH" = "true" ]; then
        push_flag="--push"
        log_info "将推送镜像到仓库"
    fi

    if [ "$NO_CACHE" = "true" ]; then
        cache_flag="--no-cache"
        log_info "无缓存构建"
    fi

    log_info "开始多架构构建..."
    log_info "支持架构: linux/amd64, linux/arm64"

    # 使用 buildx 构建多架构镜像
    docker buildx build \
        --file Dockerfile.builder \
        --platform linux/amd64,linux/arm64 \
        --tag postgres-operator:latest \
        $push_flag \
        $cache_flag \
        --progress=plain \
        .

    log_success "多架构构建完成"
}

# 运行服务
run_services() {
    log_info "启动 PostgreSQL Operator 服务..."

    # 使用多架构 compose 文件
    docker compose -f docker-compose.multiarch.yaml up -d

    log_success "服务启动完成"

    # 显示服务状态
    echo
    log_info "服务状态:"
    docker compose -f docker-compose.multiarch.yaml ps

    echo
    log_info "访问地址:"
    echo "  - PostgreSQL Operator Metrics: http://localhost:8091"
    echo "  - PostgreSQL Database: localhost:5432"
    echo "  - pgAdmin: http://localhost:8081 (admin@example.com / admin123)"
}

# 测试构建
test_build() {
    log_info "测试构建..."

    # 创建测试目录
    mkdir -p ./bin

    # 构建 builder 阶段
    docker buildx build \
        --file Dockerfile.builder \
        --target builder \
        --platform linux/amd64,linux/arm64 \
        --tag postgres-operator:test-builder \
        --progress=plain \
        .

    log_success "构建测试完成"
}

# 清理
clean_up() {
    log_info "清理镜像和容器..."

    # 停止并删除容器
    docker compose -f docker-compose.multiarch.yaml down -v || true
    docker compose -f docker-compose.yaml down -v || true

    # 删除镜像
    docker rmi postgres-operator:latest || true
    docker rmi postgres-operator:builder || true
    docker rmi postgres-operator:test-builder || true

    # 清理 buildx 缓存
    docker buildx prune -f || true

    # 删除构建输出
    rm -rf ./bin/*

    log_success "清理完成"
}

# 主函数
main() {
    local command="$1"
    shift || true

    # 解析选项
    PUSH=false
    NO_CACHE=false
    VERBOSE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --push)
                PUSH=true
                shift
                ;;
            --no-cache)
                NO_CACHE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                set -x
                shift
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 执行命令
    case $command in
        build)
            check_prerequisites
            setup_buildx
            build_multiarch
            ;;
        run)
            check_prerequisites
            run_services
            ;;
        test)
            check_prerequisites
            setup_buildx
            test_build
            ;;
        clean)
            clean_up
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            if [ -z "$command" ]; then
                log_error "请指定命令"
            else
                log_error "未知命令: $command"
            fi
            show_help
            exit 1
            ;;
    esac
}

# 错误处理
trap 'log_error "执行失败，退出码: $?"' ERR

# 执行主函数
main "$@"
