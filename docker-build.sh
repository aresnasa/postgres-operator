#!/bin/bash

set -e

echo "=== PostgreSQL Operator Docker 构建脚本 ==="
echo "适用于 Linux 环境的跨平台构建"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 函数定义
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查 Docker 和 docker-compose
check_requirements() {
    log_info "检查系统要求..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装。请先安装 Docker。"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "docker-compose 未安装。请先安装 docker-compose。"
        exit 1
    fi
    
    # 检查 Docker 是否运行
    if ! docker info &> /dev/null; then
        log_error "Docker 服务未运行。请启动 Docker 服务。"
        exit 1
    fi
    
    log_success "系统要求检查通过"
}

# 清理函数
cleanup() {
    log_info "清理旧的构建..."
    docker-compose down --remove-orphans 2>/dev/null || true
    docker system prune -f --filter "label=project=postgres-operator" 2>/dev/null || true
}

# 构建函数
build_operator() {
    log_info "开始构建 PostgreSQL Operator..."
    
    # 构建镜像
    docker-compose build --no-cache postgres-operator-builder
    
    # 运行构建
    docker-compose run --rm postgres-operator-builder
    
    # 检查构建结果
    if [ -f "bin/postgres-operator" ]; then
        log_success "二进制文件构建成功"
        ls -la bin/postgres-operator
    else
        log_error "构建失败：未找到二进制文件"
        exit 1
    fi
    
    # 构建运行时镜像
    log_info "构建运行时镜像..."
    docker-compose build postgres-operator
    
    log_success "PostgreSQL Operator 构建完成"
}

# 运行函数
run_operator() {
    log_info "启动 PostgreSQL Operator..."
    docker-compose up -d postgres-operator
    
    log_info "等待服务启动..."
    sleep 10
    
    # 检查服务状态
    if docker-compose ps postgres-operator | grep -q "Up"; then
        log_success "PostgreSQL Operator 启动成功"
        log_info "健康检查端口: http://localhost:8091"
        log_info "查看日志: docker-compose logs -f postgres-operator"
    else
        log_error "PostgreSQL Operator 启动失败"
        docker-compose logs postgres-operator
        exit 1
    fi
}

# 显示帮助
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  build    仅构建镜像"
    echo "  run      构建并运行"
    echo "  stop     停止服务"
    echo "  clean    清理所有"
    echo "  logs     查看日志"
    echo "  test     运行测试环境"
    echo "  help     显示此帮助"
    echo ""
    echo "示例:"
    echo "  $0 build         # 仅构建"
    echo "  $0 run           # 构建并运行"
    echo "  $0 test          # 运行完整测试环境"
}

# 主逻辑
case "${1:-run}" in
    "build")
        check_requirements
        cleanup
        build_operator
        ;;
    "run")
        check_requirements
        cleanup
        build_operator
        run_operator
        ;;
    "stop")
        log_info "停止所有服务..."
        docker-compose down
        log_success "服务已停止"
        ;;
    "clean")
        log_info "清理所有资源..."
        docker-compose down -v --remove-orphans
        docker system prune -f
        rm -f bin/postgres-operator
        log_success "清理完成"
        ;;
    "logs")
        docker-compose logs -f postgres-operator
        ;;
    "test")
        check_requirements
        cleanup
        build_operator
        log_info "启动完整测试环境..."
        docker-compose up -d
        log_success "测试环境启动完成"
        echo ""
        log_info "服务地址:"
        log_info "  - PostgreSQL Operator: http://localhost:8091"
        log_info "  - PostgreSQL 数据库: localhost:5432"
        log_info "  - pgAdmin: http://localhost:8080"
        echo ""
        log_info "查看日志: $0 logs"
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        log_error "未知选项: $1"
        show_help
        exit 1
        ;;
esac
