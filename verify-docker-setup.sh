#!/bin/bash

echo "=== PostgreSQL Operator Docker 配置验证 ==="
echo ""

# 检查必要文件
echo "📁 检查配置文件..."
files=(
    "docker-compose.yaml"
    "Dockerfile.builder"
    "docker-build.sh"
    ".dockerignore"
    "README-Docker.md"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "✅ $file"
    else
        echo "❌ $file 缺失"
    fi
done

echo ""
echo "🔧 检查项目结构..."

# 检查关键目录和文件
key_paths=(
    "cmd/postgres-operator/main.go"
    "internal/postgres/users_nocgo.go"
    "Makefile"
    "go.mod"
    "build/postgres-operator/Dockerfile"
)

for path in "${key_paths[@]}"; do
    if [ -e "$path" ]; then
        echo "✅ $path"
    else
        echo "❌ $path 缺失"
    fi
done

echo ""
echo "🐳 Docker 构建配置摘要:"
echo ""
echo "📦 构建流程:"
echo "1. 使用 golang:1.24-alpine 作为构建基础镜像"
echo "2. 设置 CGO_ENABLED=0 用于 Linux 静态构建"
echo "3. 运行 make setup && make build-postgres-operator-nocgo"
echo "4. 使用 UBI8 最小镜像作为运行时基础"
echo "5. 复制二进制文件和配置到运行时镜像"
echo ""
echo "🚀 使用方法:"
echo "   ./docker-build.sh build    # 仅构建"
echo "   ./docker-build.sh run      # 构建并运行"
echo "   ./docker-build.sh test     # 完整测试环境"
echo "   ./docker-build.sh help     # 显示帮助"
echo ""
echo "🌐 服务端口:"
echo "   8091  - 健康检查"
echo "   8443  - 指标服务"
echo "   5432  - PostgreSQL 数据库"
echo "   8080  - pgAdmin 管理界面"
echo ""
echo "✅ 配置验证完成！现在可以运行 ./docker-build.sh 开始构建。"
