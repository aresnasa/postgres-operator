# PostgreSQL Operator Docker 构建指南

本指南说明如何使用 Docker 和 docker-compose 在 Linux 环境下构建和运行 PostgreSQL Operator。

## 🚀 快速开始

### 前置要求

- Docker 20.10+ 
- docker-compose 1.29+
- Linux 操作系统（支持 x86_64 架构）

### 一键构建和运行

```bash
# 给脚本执行权限
chmod +x docker-build.sh

# 构建并运行 PostgreSQL Operator
./docker-build.sh run
```

## 📋 详细使用说明

### 1. 仅构建

```bash
# 仅构建 PostgreSQL Operator 镜像
./docker-build.sh build
```

### 2. 运行测试环境

```bash
# 启动完整的测试环境（包括 PostgreSQL 和 pgAdmin）
./docker-build.sh test
```

### 3. 查看日志

```bash
# 查看 PostgreSQL Operator 日志
./docker-build.sh logs

# 或者使用 docker-compose
docker-compose logs -f postgres-operator
```

### 4. 停止服务

```bash
# 停止所有服务
./docker-build.sh stop
```

### 5. 清理资源

```bash
# 清理所有 Docker 资源和构建文件
./docker-build.sh clean
```

## 🔧 手动使用 docker-compose

如果您更喜欢直接使用 docker-compose：

```bash
# 构建镜像
docker-compose build

# 仅运行构建器
docker-compose run --rm postgres-operator-builder

# 启动所有服务
docker-compose up -d

# 查看状态
docker-compose ps

# 停止服务
docker-compose down
```

## 🌐 服务端口

构建完成后，以下服务将可用：

- **PostgreSQL Operator 健康检查**: http://localhost:8091
- **PostgreSQL Operator 指标**: https://localhost:8443
- **PostgreSQL 数据库**: localhost:5432
- **pgAdmin 管理界面**: http://localhost:8080

## 🛠️ 自定义配置

### 环境变量

您可以通过修改 `docker-compose.yaml` 中的环境变量来自定义配置：

```yaml
environment:
  - PGO_NAMESPACE=your-namespace
  - CRUNCHY_DEBUG=true
  - PGO_FEATURE_GATES=YourFeature=true
```

### 构建参数

如果需要修改构建参数，编辑 `Dockerfile.builder` 中的环境变量：

```dockerfile
ENV CGO_ENABLED=0
ENV GOOS=linux
ENV GOARCH=amd64
```

## 📁 文件结构

```
├── docker-compose.yaml      # Docker Compose 配置
├── Dockerfile.builder       # 多阶段构建 Dockerfile
├── docker-build.sh         # 构建脚本
├── .dockerignore           # Docker 忽略文件
└── README-Docker.md        # 本文件
```

## 🐛 故障排除

### 构建失败

1. 检查 Docker 服务是否运行：
   ```bash
   docker info
   ```

2. 清理并重新构建：
   ```bash
   ./docker-build.sh clean
   ./docker-build.sh build
   ```

### 运行时错误

1. 查看日志：
   ```bash
   ./docker-build.sh logs
   ```

2. 检查端口冲突：
   ```bash
   netstat -tulpn | grep -E "(8080|8091|8443|5432)"
   ```

### 权限问题

如果遇到权限问题，确保 Docker 守护进程有足够的权限：

```bash
sudo usermod -aG docker $USER
newgrp docker
```

## 💡 提示和技巧

1. **构建缓存**: 首次构建可能需要较长时间，后续构建会利用 Docker 缓存加速。

2. **资源监控**: 使用以下命令监控资源使用：
   ```bash
   docker stats
   ```

3. **日志轮转**: 对于生产环境，建议配置日志轮转：
   ```bash
   docker-compose logs --tail=100 postgres-operator
   ```

4. **健康检查**: PostgreSQL Operator 包含内置健康检查，可通过以下端点验证：
   ```bash
   curl http://localhost:8091/readyz
   curl http://localhost:8091/livez
   ```

## 🚀 生产部署建议

1. 使用具体的镜像标签而不是 `latest`
2. 配置适当的资源限制
3. 使用外部数据库而不是容器内的 PostgreSQL
4. 配置持久化存储
5. 实施适当的监控和日志记录

## 🆘 获取帮助

如果遇到问题，请：

1. 查看构建日志：`./docker-build.sh logs`
2. 检查 Docker 状态：`docker-compose ps`
3. 参考官方文档：[PostgreSQL Operator Documentation](https://access.crunchydata.com/documentation/postgres-operator/)

---

**注意**: 此构建配置专门为 Linux 环境优化，使用 CGO_ENABLED=0 来避免 CGO 依赖问题。
