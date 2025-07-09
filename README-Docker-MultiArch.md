# PostgreSQL Operator Docker 部署指南

本指南介绍如何使用 Docker 和 Docker Compose 构建和运行 CrunchyData PostgreSQL Operator。

## 🏗️ 多架构支持

本项目支持 **多架构构建**，包括：
- **linux/amd64** (x86_64)
- **linux/arm64** (ARM64/Apple Silicon)

## 📁 文件说明

- `Dockerfile.builder` - 多阶段 Docker 构建文件，支持多架构
- `docker-compose.yaml` - 标准 Docker Compose 配置
- `docker-compose.multiarch.yaml` - 多架构 Docker Compose 配置
- `docker-buildx.sh` - 高级多架构构建脚本
- `multiarch.sh` - 简化的多架构构建和运行脚本
- `verify-docker-setup.sh` - 环境验证脚本

## 🚀 快速开始

### 方法一：使用简化脚本（推荐）

```bash
# 1. 验证环境
./verify-docker-setup.sh

# 2. 测试构建环境
./multiarch.sh test

# 3. 构建多架构镜像
./multiarch.sh build

# 4. 运行所有服务
./multiarch.sh run

# 5. 清理（可选）
./multiarch.sh clean
```

### 方法二：使用高级构建脚本

```bash
# 本地构建（自动选择当前架构）
./docker-buildx.sh

# 指定标签构建
./docker-buildx.sh --tag v1.0.0

# 多架构构建并推送到仓库
./docker-buildx.sh --registry docker.io/myorg --tag v1.0.0

# 使用环境变量
TAG=v1.0.0 REGISTRY=docker.io/myorg ./docker-buildx.sh

# 构建完成后清理构建器
./docker-buildx.sh --cleanup
```

### 方法三：直接使用 Docker Compose

```bash
# 标准构建和运行
docker compose up -d

# 多架构构建和运行
docker compose -f docker-compose.multiarch.yaml up -d

# 查看服务状态
docker compose ps

# 查看日志
docker compose logs -f postgres-operator
```

## 🛠️ 高级用法

### 手动多架构构建

```bash
# 1. 创建 buildx 构建器
docker buildx create --name multiarch-builder --driver docker-container --bootstrap
docker buildx use multiarch-builder

# 2. 构建多架构镜像
docker buildx build \
  --file Dockerfile.builder \
  --platform linux/amd64,linux/arm64 \
  --tag postgres-operator:latest \
  --push \
  .

# 3. 清理构建器
docker buildx rm multiarch-builder
```

### 构建特定架构

```bash
# 只构建 AMD64
docker buildx build \
  --file Dockerfile.builder \
  --platform linux/amd64 \
  --tag postgres-operator:amd64 \
  --load \
  .

# 只构建 ARM64
docker buildx build \
  --file Dockerfile.builder \
  --platform linux/arm64 \
  --tag postgres-operator:arm64 \
  --load \
  .
```

## 🌐 服务访问

启动成功后，可以访问以下服务：

- **PostgreSQL Operator Metrics**: http://localhost:8091/metrics
- **PostgreSQL Operator Health**: http://localhost:8091/readyz
- **PostgreSQL Database**: localhost:5432
  - 用户名: `testuser`
  - 密码: `testpass`
  - 数据库: `testdb`
- **pgAdmin**: http://localhost:8081
  - 邮箱: `admin@example.com`
  - 密码: `admin123`

## 🔧 故障排除

### 构建问题

```bash
# 检查 Docker Buildx 状态
docker buildx ls

# 查看构建日志
./multiarch.sh build --verbose

# 清理构建缓存
docker buildx prune -f
```

### 运行问题

```bash
# 查看服务状态
docker compose -f docker-compose.multiarch.yaml ps

# 查看详细日志
docker compose -f docker-compose.multiarch.yaml logs --tail=100

# 重启服务
docker compose -f docker-compose.multiarch.yaml restart postgres-operator
```

### 网络问题

```bash
# 检查网络
docker network ls | grep postgres-operator

# 重建网络
docker compose -f docker-compose.multiarch.yaml down
docker compose -f docker-compose.multiarch.yaml up -d
```

## 📋 系统要求

- **Docker**: >= 20.10.0
- **Docker Compose**: >= 2.0.0
- **Docker Buildx**: >= 0.8.0
- **内存**: >= 4GB
- **磁盘空间**: >= 10GB

## 🔒 安全配置

- 容器以非 root 用户运行 (UID/GID: 1001)
- 使用只读文件系统挂载
- 启用健康检查监控
- 网络隔离和防火墙规则

## 📝 环境变量

| 变量名 | 描述 | 默认值 |
|--------|------|--------|
| `PGO_NAMESPACE` | Operator 命名空间 | `postgres-operator` |
| `CRUNCHY_DEBUG` | 调试模式 | `true` |
| `PGO_FEATURE_GATES` | 功能开关 | `AllAlpha=true` |
| `TAG` | 镜像标签 | `latest` |
| `REGISTRY` | 镜像仓库 | - |

## 🤝 贡献

欢迎提交问题和改进建议！

## 📄 许可证

本项目遵循 Apache 2.0 许可证。
