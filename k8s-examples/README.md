# Kubernetes PostgreSQL 集群配置说明

本文档说明如何使用 CrunchyData PostgreSQL Operator 在 Kubernetes 中配置和部署 PostgreSQL 集群。

## 📁 文件说明

- `postgres-cluster-sample.yaml` - 基础示例配置，适合开发和测试环境
- `postgres-cluster-production.yaml` - 生产环境配置，包含高可用、备份、监控等完整功能

## 🚀 快速部署

### 1. 基础环境部署

```bash
# 部署 Operator
./scripts/k8s-deploy.sh deploy

# 创建基础 PostgreSQL 集群
kubectl apply -f k8s-examples/postgres-cluster-sample.yaml

# 查看集群状态
kubectl -n postgres-operator get postgrescluster
kubectl -n postgres-operator get pods
```

### 2. 生产环境部署

```bash
# 首先创建必要的 Secret (如果使用 S3 备份)
kubectl -n postgres-operator create secret generic postgres-backup-s3-secret \
  --from-literal=AWS_ACCESS_KEY_ID=your-access-key \
  --from-literal=AWS_SECRET_ACCESS_KEY=your-secret-key

# 创建 TLS Secret (可选)
kubectl -n postgres-operator create secret tls postgres-production-tls \
  --cert=path/to/cert.pem \
  --key=path/to/key.pem

# 部署生产级集群
kubectl apply -f k8s-examples/postgres-cluster-production.yaml
```

## ⚙️ 配置项说明

### 基础配置

#### PostgreSQL 版本
```yaml
spec:
  postgresVersion: 16  # 支持 12, 13, 14, 15, 16
```

#### 实例配置
```yaml
instances:
- name: instance1
  replicas: 1              # 副本数量
  dataVolumeClaimSpec:
    accessModes:
    - "ReadWriteOnce"
    storageClassName: ""   # 存储类名称，空值使用默认
    resources:
      requests:
        storage: 2Gi       # 存储大小
```

#### 资源限制
```yaml
resources:
  requests:
    cpu: "200m"           # CPU 请求
    memory: "512Mi"       # 内存请求
  limits:
    cpu: "1000m"          # CPU 限制
    memory: "1Gi"         # 内存限制
```

### 高可用配置

#### 多实例配置
```yaml
instances:
- name: primary          # 主实例组
  replicas: 1
- name: replica          # 只读副本组
  replicas: 2
```

#### 反亲和性
```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:  # 强制
    - topologyKey: kubernetes.io/hostname
      labelSelector:
        matchLabels:
          postgres-operator.crunchydata.com/cluster: cluster-name

    preferredDuringSchedulingIgnoredDuringExecution:  # 偏好
    - weight: 100
      podAffinityTerm:
        topologyKey: kubernetes.io/hostname
```

### 备份配置

#### 本地备份
```yaml
backups:
  pgbackrest:
    repos:
    - name: repo1
      schedules:
        full: "0 2 * * 0"           # Cron 格式：周日凌晨2点
        differential: "0 2 * * 1-6"  # 周一到周六
        incremental: "0 */6 * * *"   # 每6小时
      volume:
        volumeClaimSpec:
          accessModes:
          - "ReadWriteOnce"
          resources:
            requests:
              storage: 2Gi
```

#### S3 备份
```yaml
repos:
- name: repo2
  s3:
    bucket: "postgres-backups"
    endpoint: "https://s3.amazonaws.com"
    region: "us-east-1"
  secretRef:
    name: postgres-backup-s3-secret
```

### 连接池配置

#### PgBouncer 配置
```yaml
proxy:
  pgBouncer:
    replicas: 1
    config:
      global:
        pool_mode: "transaction"    # session, transaction, statement
        max_client_conn: "100"      # 最大客户端连接
        default_pool_size: "10"     # 默认连接池大小
        reserve_pool_size: "5"      # 保留连接池大小
```

### PostgreSQL 配置

#### 基础参数
```yaml
patroni:
  dynamicConfiguration:
    postgresql:
      parameters:
        # 内存配置
        shared_buffers: "128MB"           # 共享缓冲区
        effective_cache_size: "384MB"     # 有效缓存大小
        work_mem: "4MB"                   # 工作内存
        maintenance_work_mem: "64MB"      # 维护工作内存

        # 连接配置
        max_connections: "100"            # 最大连接数

        # WAL 配置
        wal_level: "replica"              # WAL 级别
        max_wal_size: "1GB"               # 最大 WAL 大小
        min_wal_size: "80MB"              # 最小 WAL 大小

        # 性能配置
        checkpoint_completion_target: "0.9"
        random_page_cost: "1.1"           # SSD 优化
        effective_io_concurrency: "200"
```

### 用户和数据库配置

#### 用户配置
```yaml
users:
- name: app-user
  databases:
  - "app-db"
  options: "CREATEDB CREATEROLE"  # 权限选项

- name: readonly-user
  databases:
  - "app-db"
  options: "NOSUPERUSER NOCREATEDB NOCREATEROLE"
```

#### 数据库配置
```yaml
databases:
- name: app-db
  options: "LC_COLLATE=en_US.UTF-8 LC_CTYPE=en_US.UTF-8"
```

### 监控配置

#### PostgreSQL Exporter
```yaml
monitoring:
  pgmonitor:
    exporter:
      resources:
        requests:
          cpu: "10m"
          memory: "32Mi"
        limits:
          cpu: "100m"
          memory: "64Mi"
```

## 🔧 常用操作

### 获取连接信息

```bash
# 获取服务名称
kubectl -n postgres-operator get svc

# 获取用户密码
kubectl -n postgres-operator get secret postgres-sample-pguser-app-user -o jsonpath='{.data.password}' | base64 -d

# 连接到数据库
kubectl -n postgres-operator exec -it deployment/postgres-sample-instance1 -- psql -U app-user -d app-db
```

### 备份和恢复

```bash
# 手动触发备份
kubectl -n postgres-operator annotate postgrescluster postgres-sample \
  postgres-operator.crunchydata.com/pgbackrest-backup="$(date)"

# 查看备份状态
kubectl -n postgres-operator describe postgrescluster postgres-sample

# 从备份恢复 (需要创建新集群)
```

### 扩容操作

```bash
# 修改副本数量
kubectl -n postgres-operator patch postgrescluster postgres-sample \
  --type='merge' -p='{"spec":{"instances":[{"name":"instance1","replicas":3}]}}'

# 增加存储 (注意：只能增加不能减少)
kubectl -n postgres-operator patch postgrescluster postgres-sample \
  --type='merge' -p='{"spec":{"instances":[{"name":"instance1","dataVolumeClaimSpec":{"resources":{"requests":{"storage":"10Gi"}}}}]}}'
```

### 故障排除

```bash
# 查看集群状态
kubectl -n postgres-operator get postgrescluster postgres-sample -o yaml

# 查看 Pod 日志
kubectl -n postgres-operator logs deployment/postgres-sample-instance1

# 查看事件
kubectl -n postgres-operator get events --sort-by='.lastTimestamp'

# 查看 Operator 日志
kubectl -n postgres-operator logs deployment/postgres-operator
```

## 🚨 安全最佳实践

### 1. 网络策略
- 使用 NetworkPolicy 限制访问
- 只允许必要的命名空间访问数据库
- 分离读写流量

### 2. RBAC 配置
- 为应用创建专用的 ServiceAccount
- 使用最小权限原则
- 定期轮换密码

### 3. 加密配置
- 启用 SSL/TLS 连接
- 使用自定义证书
- 配置数据加密

### 4. 备份安全
- 加密备份数据
- 使用独立的存储账户
- 定期测试恢复流程

## 🔍 性能优化

### 1. 存储优化
- 使用 SSD 存储类
- 配置适当的 IOPS
- 监控存储使用情况

### 2. 内存优化
- 根据工作负载调整 shared_buffers
- 优化 work_mem 设置
- 配置 huge pages

### 3. 连接池优化
- 使用 PgBouncer 连接池
- 配置合适的池大小
- 监控连接使用情况

### 4. 查询优化
- 定期更新统计信息
- 配置自动清理
- 监控慢查询

## 📊 监控指标

### 重要指标
- CPU 和内存使用率
- 磁盘 I/O 和存储使用
- 连接数和活跃查询
- 复制延迟
- 备份状态

### 告警规则
- 主库故障切换
- 复制延迟过高
- 存储空间不足
- 连接数过多
- 备份失败

## 📚 参考资源

- [CrunchyData PostgreSQL Operator 文档](https://postgres-operator.readthedocs.io/)
- [PostgreSQL 官方文档](https://www.postgresql.org/docs/)
- [Kubernetes 存储文档](https://kubernetes.io/docs/concepts/storage/)
- [PgBouncer 配置指南](https://www.pgbouncer.org/config.html)
