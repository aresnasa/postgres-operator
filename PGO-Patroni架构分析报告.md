# PGO + Patroni 架构分析报告

## 概述

经过详细验证，**CrunchyData PostgreSQL Operator (PGO) 底层确实依赖 Patroni 进行故障迁移和恢复**。这是一个分层架构，其中：

- **PGO**: 负责 Kubernetes 层面的资源管理和声明式配置
- **Patroni**: 负责 PostgreSQL 层面的高可用性、故障检测和自动故障转移

## 架构验证

### 1. Pod 容器结构分析

```bash
❯ kubectl describe pod demo-cluster-instance1-fzt2-0
```

**关键发现**:
- Pod 中有 4 个容器，其中 `database` 容器的启动命令是：`patroni /etc/patroni`
- 环境变量中包含大量 `PATRONI_*` 配置项
- 容器标签中包含 `postgres-operator.crunchydata.com/patroni=demo-cluster-ha`

### 2. Patroni 进程验证

```bash
❯ kubectl exec -it demo-cluster-instance1-fzt2-0 -c database -- ps aux
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
postgres    48  0.1  0.1 562104 34428 ?        Ssl  08:14   0:03 /usr/bin/python3 /usr/local/bin/patroni /etc/patroni
postgres    97  0.0  0.0 213712 27208 ?        S    08:14   0:00 postgres -D /pgdata/pg16 --config-file=/pgdata/pg16/postgresql.conf
```

**关键发现**:
- PID 48: Patroni 主进程 (`/usr/bin/python3 /usr/local/bin/patroni`)
- PID 97: PostgreSQL 进程，由 Patroni 管理启动
- Patroni 作为主进程管理 PostgreSQL 实例

### 3. Patroni 集群状态

```bash
❯ kubectl exec -it demo-cluster-instance1-fzt2-0 -c database -- patronictl list
+ Cluster: demo-cluster-ha (7523508303005618264) -----------+--------+---------+----+-----------+
| Member                        | Host                      | Role   | State   | TL | Lag in MB |
+-------------------------------+---------------------------+--------+---------+----+-----------+
| demo-cluster-instance1-fzt2-0 | demo-cluster-instance1-fzt2-0.demo-cluster-pods | Leader | running |  1 |           |
+-------------------------------+---------------------------+--------+---------+----+-----------+
```

**关键发现**:
- 集群名称: `demo-cluster-ha`
- 当前实例是 `Leader` 角色
- 状态: `running`
- Timeline: 1（无故障转移）

### 4. Service Endpoints 管理

```bash
❯ kubectl get endpoints demo-cluster-ha -o yaml
metadata:
  annotations:
    acquireTime: "2025-07-05T08:14:43.163220+00:00"
    leader: demo-cluster-instance1-fzt2-0
    optime: "50331648"
    renewTime: "2025-07-05T08:34:23.259790+00:00"
    retain_slots: '["demo_cluster_instance1_fzt2_0"]'
    slots: '{"demo_cluster_instance1_fzt2_0":50331648}'
    transitions: "0"
    ttl: "30"
  labels:
    postgres-operator.crunchydata.com/patroni: demo-cluster-ha
```

**关键发现**:
- Endpoints 包含 Patroni 的元数据注释
- `leader`: 当前主节点标识
- `optime`: 操作时间戳
- `renewTime`: 续租时间（心跳机制）
- `ttl: 30`: 生存时间 30 秒
- `transitions: 0`: 无故障转移次数

## 架构层次分析

### 第一层：Kubernetes Operator (PGO)
- **职责**:
  - 管理 StatefulSet, Services, ConfigMaps, Secrets
  - 处理 PostgresCluster CRD
  - 生成 Patroni 配置
  - 管理备份、用户、证书等

### 第二层：Patroni 高可用管理
- **职责**:
  - PostgreSQL 实例生命周期管理
  - 故障检测和自动故障转移
  - 主从复制管理
  - 脑裂防护
  - REST API 提供集群状态

### 第三层：PostgreSQL 数据库
- **职责**:
  - 实际的数据存储和查询处理
  - 由 Patroni 管理启动/停止
  - 接收 Patroni 的配置更新

## Patroni 配置分析

```yaml
# /etc/patroni 配置（简化）
loop_wait: 10                    # 心跳间隔
ttl: 30                          # 租约时间
postgresql:
  parameters:
    archive_command: pgbackrest --stanza=db archive-push "%p"
    archive_mode: 'on'
    wal_level: logical
    ssl: 'on'
  pg_hba:
    - hostssl replication "_crunchyrepl" all "cert"
    - hostssl all all all "scram-sha-256"
  use_pg_rewind: true
  use_slots: false
```

## 故障转移机制

### 1. 故障检测
- Patroni 每 10 秒检查一次集群状态 (`loop_wait: 10`)
- 通过 Kubernetes Endpoints 进行分布式锁管理
- TTL 30 秒，超时则认为节点故障

### 2. 自动故障转移
- 当主节点故障时，Patroni 在从节点中选举新主节点
- 更新 Kubernetes Service Endpoints 指向新主节点
- 自动处理 timeline 切换和 WAL 同步

### 3. 脑裂防护
- 使用 Kubernetes API 作为分布式锁存储
- 只有获得锁的节点才能成为主节点
- 防止多个节点同时成为主节点

## Service 架构说明

### `demo-cluster-ha` (ClusterIP Service)
- **用途**: 提供高可用的数据库连接入口
- **管理**: 由 Patroni 通过 Kubernetes API 动态更新 Endpoints
- **故障转移**: 自动指向当前的主节点

### `demo-cluster-primary` (Headless Service)
- **用途**: 服务发现和静态连接
- **管理**: PGO 管理，Endpoints 指向 `demo-cluster-ha`
- **特点**: 提供稳定的 DNS 名称

## 优势分析

1. **分层责任**:
   - PGO 处理 Kubernetes 原生资源
   - Patroni 专注于 PostgreSQL 高可用

2. **故障恢复速度**:
   - Patroni 的快速故障检测（10 秒心跳）
   - 自动故障转移（通常 < 1 分钟）

3. **一致性保证**:
   - 分布式锁防止脑裂
   - WAL 同步确保数据一致性

4. **可观测性**:
   - Patroni REST API 提供集群状态
   - PGO 暴露 Kubernetes 指标

## 结论

**是的，PGO 底层确实依赖 Patroni 进行故障迁移和恢复**。这是一个设计良好的分层架构：

- **PGO**: 提供 Kubernetes 原生的声明式管理
- **Patroni**: 提供 PostgreSQL 专业的高可用性能力

这种架构结合了 Kubernetes Operator 模式的优势和 Patroni 成熟的 PostgreSQL 高可用解决方案，是目前云原生环境下部署高可用 PostgreSQL 的最佳实践之一。

---

生成时间: 2025-07-05
验证集群: demo-cluster
架构状态: ✅ 完全验证
