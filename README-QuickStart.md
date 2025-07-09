# PostgreSQL Operator - 快速开始指南

这是 CrunchyData PostgreSQL Operator 的快速部署指南，支持 Docker 本地开发和 Kubernetes 生产部署。

## 🚀 快速开始

### 前置要求

- Docker (>=20.10) 和 Docker Compose
- Kubernetes 集群 (用于 K8s 部署)
- kubectl (用于 K8s 部署)

### 方式一：Docker 本地开发

#### 1. 构建并运行

```bash
# 基础构建和运行
docker-compose up -d postgres-operator

# 构建二进制文件到本地
docker-compose run --rm postgres-operator-builder

# 运行完整环境 (包括测试数据库和 pgAdmin)
docker-compose up -d
```

#### 2. 多架构构建

```bash
# 构建支持 ARM64 和 AMD64 的镜像
./scripts/build-multiarch.sh

# 推送到镜像仓库 (用于 K8s 部署)
./scripts/build-multiarch.sh --push --registry your-registry.com --tag v1.0.0
```

#### 3. 访问服务

- **PostgreSQL Operator 管理端口**: <http://localhost:8091/readyz>
- **测试数据库**: localhost:5432 (testuser/testpass)
- **pgAdmin**: <http://localhost:8090> (admin@example.com / admin123)

### 方式二：Kubernetes 生产部署

#### 1. 构建并推送镜像

```bash
# 构建多架构镜像并推送到仓库
./scripts/build-multiarch.sh --push --registry your-registry.com --tag v1.0.0
```

#### 2. 部署到 Kubernetes

```bash
# 仅部署 Operator
./scripts/k8s-deploy.sh deploy

# 部署 Operator 并创建示例 PostgreSQL 集群
PGO_IMAGE=your-registry.com/postgres-operator:v1.0.0 ./scripts/k8s-deploy.sh deploy-full

# 查看部署状态
./scripts/k8s-deploy.sh status

# 获取 PostgreSQL 连接信息
./scripts/k8s-deploy.sh connect
```

#### 3. 手动部署 (使用 kubectl)

```bash
# 创建命名空间
kubectl apply -k ./config/namespace

# 部署 CRDs
kubectl apply --server-side -k ./config/crd

# 部署 RBAC
kubectl apply -k ./config/rbac

# 部署 Operator
kubectl apply -k ./config/default

# 创建 PostgreSQL 集群
kubectl apply -f examples/postgrescluster/postgrescluster.yaml
```

## 📋 管理命令

### Docker 环境

```bash
# 查看 Operator 日志
docker-compose logs -f postgres-operator

# 重启 Operator
docker-compose restart postgres-operator

# 清理环境
docker-compose down -v
```

### Kubernetes 环境

```bash
# 查看 Operator 状态
kubectl -n postgres-operator get pods

# 查看 Operator 日志
kubectl -n postgres-operator logs -l postgres-operator.crunchydata.com/control-plane=postgres-operator

# 查看 PostgreSQL 集群
kubectl -n postgres-operator get postgrescluster

# 连接到 PostgreSQL
kubectl -n postgres-operator exec -it deployment/hippo-instance1 -- psql -U postgres -d hippo

# 清理所有资源
./scripts/k8s-deploy.sh cleanup
```

## 🔧 配置选项

### 环境变量

| 变量名 | 默认值 | 描述 |
|--------|--------|------|
| `PGO_NAMESPACE` | `postgres-operator` | Operator 运行的命名空间 |
| `CRUNCHY_DEBUG` | `true` | 启用调试模式 |
| `PGO_FEATURE_GATES` | `AllAlpha=true` | 功能门控 |
| `PGO_IMAGE` | `localhost/postgres-operator:latest` | Operator 镜像 |

### 构建选项

```bash
# 自定义镜像名称和标签
./scripts/build-multiarch.sh --name my-operator --tag v2.0.0

# 使用不同的 Dockerfile
./scripts/build-multiarch.sh --dockerfile Dockerfile.custom

# 推送到私有仓库
./scripts/build-multiarch.sh --push --registry private-registry.com
```

### Kubernetes 配置

```bash
# 使用自定义命名空间
PGO_NAMESPACE=my-namespace ./scripts/k8s-deploy.sh deploy

# 使用自定义镜像
PGO_IMAGE=my-registry.com/postgres-operator:v1.0.0 ./scripts/k8s-deploy.sh deploy
```

## 🔍 故障排除

### 常见问题

#### 1. Docker 构建失败

```bash
# 检查 Docker 版本
docker --version

# 清理 Docker 缓存
docker builder prune -a

# 重新构建
docker-compose build --no-cache postgres-operator
```

#### 2. Kubernetes 部署失败

```bash
# 检查集群连接
kubectl cluster-info

# 检查节点状态
kubectl get nodes

# 查看 Pod 错误
kubectl -n postgres-operator describe pod <pod-name>
```

#### 3. PostgreSQL 集群创建失败

```bash
# 查看集群状态
kubectl -n postgres-operator get postgrescluster hippo -o yaml

# 查看相关事件
kubectl -n postgres-operator get events --sort-by='.lastTimestamp'

# 检查存储类
kubectl get storageclass
```

### 调试技巧

```bash
# 进入 Operator 容器
docker-compose exec postgres-operator sh

# 在 Kubernetes 中调试
kubectl -n postgres-operator exec -it deployment/postgres-operator -- sh

# 检查 Operator 配置
kubectl -n postgres-operator get configmap

# 查看 RBAC 权限
kubectl auth can-i '*' '*' --as=system:serviceaccount:postgres-operator:postgres-operator
```

## 📖 更多资源

- [PostgreSQL Operator 官方文档](https://postgres-operator.readthedocs.io/)
- [CrunchyData 官网](https://www.crunchydata.com/)
- [Kubernetes PostgreSQL 最佳实践](https://kubernetes.io/docs/concepts/workloads/)

## 🤝 贡献

1. Fork 项目
2. 创建功能分支: `git checkout -b feature/new-feature`
3. 提交更改: `git commit -am 'Add new feature'`
4. 推送分支: `git push origin feature/new-feature`
5. 创建 Pull Request

## 📄 许可证

本项目采用 Apache 2.0 许可证 - 查看 [LICENSE.md](LICENSE.md) 文件了解详情。
