#!/bin/bash

set -e  # 遇到错误时停止

echo "=== PostgreSQL Operator 构建脚本 ==="

# 方案1：尝试使用 CGO 但设置特殊的编译器标志
try_cgo_build() {
    echo "尝试使用 CGO 构建..."
    export MACOSX_DEPLOYMENT_TARGET=15.4
    export CGO_ENABLED=1
    export CGO_CFLAGS="-Wno-error=unused-function -Wno-error=declaration-after-statement"

    echo "设置环境变量:"
    echo "MACOSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET"
    echo "CGO_ENABLED=$CGO_ENABLED"
    echo "CGO_CFLAGS=$CGO_CFLAGS"
    echo

    go build \
        -ldflags '-X "main.versionString=dev-build"' \
        -trimpath \
        -o bin/postgres-operator \
        ./cmd/postgres-operator
}

# 方案2：禁用 CGO 构建
try_nocgo_build() {
    echo "尝试禁用 CGO 构建..."
    export CGO_ENABLED=0

    echo "设置环境变量:"
    echo "CGO_ENABLED=$CGO_ENABLED"
    echo

    go build \
        -tags="!cgo" \
        -ldflags '-X "main.versionString=dev-build"' \
        -trimpath \
        -o bin/postgres-operator \
        ./cmd/postgres-operator
}

# 清理之前的构建
echo "清理之前的构建..."
rm -f bin/postgres-operator
mkdir -p bin

# 首先尝试 CGO 构建
if try_cgo_build 2>/dev/null; then
    echo "✅ CGO 构建成功"
elif try_nocgo_build 2>/dev/null; then
    echo "✅ 无 CGO 构建成功"
    echo "⚠️  注意：某些功能可能不可用（如 SQL 解析功能）"
else
    echo "❌ 两种构建方式都失败了"
    echo "尝试手动构建..."
    make build-postgres-operator
fi

echo
echo "构建完成，检查结果:"
ls -la bin/

if [ -f bin/postgres-operator ]; then
    echo "✅ 构建成功！"
    echo "文件大小: $(du -h bin/postgres-operator | cut -f1)"
    echo "可以运行: ./bin/postgres-operator --help"
else
    echo "❌ 构建失败，未找到二进制文件"
    exit 1
fi
