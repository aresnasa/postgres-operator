#!/bin/bash

set -e  # 遇到错误时停止

echo "=== PostgreSQL Operator 构建脚本 ==="

# 设置环境变量解决 macOS 兼容性问题
export MACOSX_DEPLOYMENT_TARGET=15.4
export CGO_ENABLED=1

# 显示当前环境
echo "Go 版本: $(go version)"
echo "MACOSX_DEPLOYMENT_TARGET: $MACOSX_DEPLOYMENT_TARGET"
echo "CGO_ENABLED: $CGO_ENABLED"
echo "当前目录: $(pwd)"
echo ""

# 确保 bin 目录存在
mkdir -p bin

# 清理之前的构建
echo "清理之前的构建..."
rm -f bin/postgres-operator

# 下载依赖
echo "下载 Go 模块..."
go mod download

# 构建
echo "开始构建 postgres-operator..."
go build \
    -v \
    -ldflags '-X "main.versionString=dev-build"' \
    -trimpath \
    -o bin/postgres-operator \
    ./cmd/postgres-operator

# 检查结果
if [ -f bin/postgres-operator ]; then
    echo ""
    echo "=== 构建成功! ==="
    echo "二进制文件位置: bin/postgres-operator"
    echo "文件大小: $(du -h bin/postgres-operator | cut -f1)"
    echo "文件信息: $(file bin/postgres-operator)"
else
    echo ""
    echo "=== 构建失败! ==="
    echo "未找到 bin/postgres-operator 文件"
    exit 1
fi
