# 多阶段构建 Dockerfile，专门用于 Linux 环境构建
FROM golang:1.24-alpine AS builder

# 安装必要的构建工具
RUN apk add --no-cache \
    git \
    make \
    bash \
    gcc \
    musl-dev

# 设置工作目录
WORKDIR /app

# 复制 go mod 文件并下载依赖
COPY go.mod go.sum ./
RUN go mod download

# 复制源代码
COPY . .

# 设置构建环境变量
ENV CGO_ENABLED=0
ENV GOOS=linux
ENV GOARCH=amd64

# 创建输出目录
RUN mkdir -p /app/bin

# 运行 setup 和构建
RUN echo "=== 开始构建 PostgreSQL Operator ===" && \
    make setup && \
    make build-postgres-operator-nocgo && \
    echo "=== 构建完成 ===" && \
    ls -la bin/

# 验证构建结果
RUN if [ -f "bin/postgres-operator" ]; then \
        echo "✅ 构建成功" && \
        file bin/postgres-operator && \
        ./bin/postgres-operator --version || echo "Binary created successfully"; \
    else \
        echo "❌ 构建失败：未找到二进制文件" && \
        exit 1; \
    fi

# 运行时镜像
FROM registry.access.redhat.com/ubi8/ubi-minimal AS runtime

# 安装必要的运行时依赖
RUN microdnf update -y && \
    microdnf install -y ca-certificates && \
    microdnf clean all

# 从构建阶段复制二进制文件
COPY --from=builder /app/bin/postgres-operator /usr/local/bin/postgres-operator

# 复制许可证文件
COPY --from=builder /app/licenses /licenses

# 创建配置目录
RUN mkdir -p /opt/crunchy/conf

# 复制查询配置文件
COPY --from=builder /app/hack/tools/queries /opt/crunchy/conf

# 设置权限
RUN chgrp -R 0 /opt/crunchy/conf && \
    chmod -R g=u /opt/crunchy/conf && \
    chmod +x /usr/local/bin/postgres-operator

# 使用非 root 用户
USER 2

# 暴露端口
EXPOSE 8080 8443 8091

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8091/readyz || exit 1

# 启动命令
CMD ["postgres-operator"]
