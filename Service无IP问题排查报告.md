# PostgreSQL Service 无 IP 问题排查报告

## 问题描述

用户发现 `demo-cluster-primary` Service 没有分配 ClusterIP，显示为 `None`，并且 `SELECTOR` 也显示为 `<none>`。

## 问题分析

### 1. Service 架构分析

通过检查发现，这是 CrunchyData PostgreSQL Operator 的正常设计模式：

```bash
❯ kubectl get svc -l postgres-operator.crunchydata.com/cluster=demo-cluster -o wide
NAME                     TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE     SELECTOR
demo-cluster-ha          ClusterIP   10.102.150.246   <none>        5432/TCP   2m46s   <none>
demo-cluster-ha-config   ClusterIP   None             <none>        <none>     2m46s   <none>
demo-cluster-pods        ClusterIP   None             <none>        <none>     2m46s   postgres-operator.crunchydata.com/cluster=demo-cluster
demo-cluster-primary     ClusterIP   None             <none>        5432/TCP   2m46s   <none>
demo-cluster-replicas    ClusterIP   10.111.42.233    <none>        5432/TCP   2m46s   postgres-operator.crunchydata.com/cluster=demo-cluster,postgres-operator.crunchydata.com/role=replica
```

### 2. Service 类型说明

1. **`demo-cluster-primary`**: Headless Service (ClusterIP: None)
   - 通过 Endpoints 手动管理连接路由
   - 指向 `demo-cluster-ha` Service 的 IP

2. **`demo-cluster-ha`**: 真正的 ClusterIP Service
   - 提供高可用性的连接点
   - 由 Patroni 管理自动故障转移

3. **`demo-cluster-replicas`**: 只读连接 Service
   - 用于只读查询负载均衡

### 3. Endpoints 分析

```bash
❯ kubectl get endpoints demo-cluster-primary -o yaml
```

`demo-cluster-primary` 的 Endpoints 指向 `demo-cluster-ha` 的 IP (10.102.150.246)，这是一个路由层，而不是直接指向 Pod IP。

## 根本原因

这**不是问题**，而是 PostgreSQL Operator 的正常架构设计：

1. **Headless Service**: `demo-cluster-primary` 是 Headless Service，用于服务发现
2. **手动 Endpoints**: Operator 通过手动管理 Endpoints 来控制连接路由
3. **高可用架构**: 通过 `demo-cluster-ha` 提供 Patroni 管理的高可用连接

## 真正的问题

在排查过程中发现了一个真正的问题：

### Operator 用户创建失败

```log
time="2025-07-05T08:15:12Z" level=error msg="Reconciler error" PostgresCluster=default/demo-cluster controller=postgrescluster controllerGroup=postgres-operator.crunchydata.com controllerKind=PostgresCluster error="unable to upgrade connection: you must specify at least 1 of stdin, stdout, stderr" file="internal/controller/postgrescluster/postgres.go:698" func="postgrescluster.(*Reconciler).reconcilePostgresUsersInPostgreSQL" name=demo-cluster namespace=default reconcileID=643c66c5-e721-43f3-b37b-bd0e6affa76d version=
```

Operator 在尝试创建用户时遇到了 `kubectl exec` 相关的错误。

## 解决方案

### 1. 临时解决方案（手动创建用户）

```bash
# 手动创建用户
kubectl exec -it demo-cluster-instance1-fzt2-0 -c database -- psql -U postgres -c "CREATE USER \"demo-cluster\" WITH CREATEDB PASSWORD 'W6-NE7-GsgayBC.4_Z<[w6.V';"

# 创建数据库
kubectl exec -it demo-cluster-instance1-fzt2-0 -c database -- psql -U postgres -c "CREATE DATABASE \"demo-cluster\" OWNER \"demo-cluster\";"
```

### 2. 连接测试

```bash
# 内部连接测试
kubectl exec -it demo-cluster-instance1-fzt2-0 -c database -- bash -c "PGPASSWORD='W6-NE7-GsgayBC.4_Z<[w6.V' psql -h demo-cluster-primary -U demo-cluster -c \"SELECT 'Success! Connected via demo-cluster-primary' as result;\""

# 外部连接测试
kubectl run test-external --rm -it --image=postgres:16 --env="PGPASSWORD=W6-NE7-GsgayBC.4_Z<[w6.V" -- psql -h demo-cluster-ha -U demo-cluster -c "SELECT 'External connection successful' as result;"
```

## 验证结果

✅ **Service 架构正常**: `demo-cluster-primary` 是 Headless Service，这是正常的设计
✅ **Endpoints 正常**: 指向 `demo-cluster-ha` Service IP
✅ **连接测试成功**: 内部和外部连接都能正常工作
✅ **数据库可用**: 用户创建成功，数据库可正常使用

## 推荐的连接方式

1. **应用连接**: 使用 `demo-cluster-ha` Service 进行读写连接
2. **只读连接**: 使用 `demo-cluster-replicas` Service 进行只读连接
3. **服务发现**: 使用 `demo-cluster-primary` 进行服务发现

## 连接字符串示例

```bash
# 从 Secret 获取连接信息
kubectl get secret demo-cluster-pguser-demo-cluster -o jsonpath='{.data.uri}' | base64 -d

# 结果: postgresql://demo-cluster:W6-NE7-GsgayBC.4_Z%3C%5Bw6.V@demo-cluster-primary.default.svc:5432/demo-cluster
```

## 结论

**Service 没有 IP 不是问题**，而是 PostgreSQL Operator 的正常架构设计。真正的问题是 Operator 的用户创建功能有 bug，但通过手动创建用户已经解决。集群现在完全可用。

---

生成时间: $(date)
状态: ✅ 问题已解决
