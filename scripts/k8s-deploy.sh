#!/bin/bash
set -euo pipefail

# PostgreSQL Operator Kubernetes 部署脚本

# 配置变量
NAMESPACE=${PGO_NAMESPACE:-"postgres-operator"}
OPERATOR_IMAGE=${PGO_IMAGE:-"localhost/postgres-operator:latest"}
ACTION=${1:-"deploy"}

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查依赖
check_dependencies() {
    log_info "检查依赖..."

    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安装"
        exit 1
    fi

    if ! command -v kustomize &> /dev/null; then
        log_warn "kustomize 未安装，尝试使用 kubectl kustomize"
    fi

    # 检查 Kubernetes 连接
    if ! kubectl cluster-info &> /dev/null; then
        log_error "无法连接到 Kubernetes 集群"
        log_info "请检查 kubeconfig 设置"
        exit 1
    fi

    log_info "Kubernetes 集群信息:"
    kubectl cluster-info | head -1
}

# 创建命名空间
create_namespace() {
    log_step "创建命名空间: ${NAMESPACE}"

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${NAMESPACE}
  labels:
    name: ${NAMESPACE}
    postgres-operator.crunchydata.com/control-plane: postgres-operator
EOF

    log_info "命名空间 ${NAMESPACE} 已创建"
}

# 部署 CRD
deploy_crds() {
    log_step "部署自定义资源定义 (CRDs)..."

    kubectl apply --server-side -k ./config/crd

    # 等待 CRD 就绪
    log_info "等待 CRDs 就绪..."
    kubectl wait --for condition=established --timeout=60s crd/postgresclusters.postgres-operator.crunchydata.com

    log_info "CRDs 部署完成"
}

# 部署 RBAC
deploy_rbac() {
    log_step "部署 RBAC 配置..."

    kubectl apply -k ./config/rbac

    log_info "RBAC 配置部署完成"
}

# 创建自定义 kustomization
create_custom_kustomization() {
    log_step "创建自定义配置..."

    mkdir -p k8s-deploy

    cat > k8s-deploy/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${NAMESPACE}

labels:
- includeSelectors: true
  pairs:
    postgres-operator.crunchydata.com/control-plane: postgres-operator

resources:
- ../config/manager

images:
- name: postgres-operator
  newName: ${OPERATOR_IMAGE%:*}
  newTag: ${OPERATOR_IMAGE#*:}

patches:
- target:
    kind: Deployment
    name: postgres-operator
  patch: |-
    - op: add
      path: /spec/template/spec/containers/0/env/-
      value:
        name: PGO_NAMESPACE
        valueFrom:
          fieldRef:
            fieldPath: metadata.namespace
    - op: add
      path: /spec/template/spec/containers/0/env/-
      value:
        name: CRUNCHY_DEBUG
        value: "true"
    - op: add
      path: /spec/template/spec/containers/0/env/-
      value:
        name: PGO_FEATURE_GATES
        value: "AllAlpha=true"

EOF

    log_info "自定义配置已创建"
}

# 部署 Operator
deploy_operator() {
    log_step "部署 PostgreSQL Operator..."

    create_custom_kustomization

    kubectl apply -k ./k8s-deploy

    # 等待 Deployment 就绪
    log_info "等待 Operator 就绪..."
    kubectl -n ${NAMESPACE} wait --for=condition=available --timeout=300s deployment/postgres-operator

    log_info "PostgreSQL Operator 部署完成"
}

# 验证部署
verify_deployment() {
    log_step "验证部署状态..."

    log_info "检查 Operator Pod 状态:"
    kubectl -n ${NAMESPACE} get pods -l postgres-operator.crunchydata.com/control-plane=postgres-operator

    log_info "检查 Operator 日志:"
    kubectl -n ${NAMESPACE} logs -l postgres-operator.crunchydata.com/control-plane=postgres-operator --tail=10

    log_info "检查 CRDs:"
    kubectl get crd | grep postgres-operator

    log_info "检查服务:"
    kubectl -n ${NAMESPACE} get svc
}

# 创建示例 PostgreSQL 集群
create_example_cluster() {
    log_step "创建示例 PostgreSQL 集群..."

    cat <<EOF | kubectl apply -f -
apiVersion: postgres-operator.crunchydata.com/v1beta1
kind: PostgresCluster
metadata:
  name: hippo
  namespace: ${NAMESPACE}
spec:
  postgresVersion: 16
  instances:
    - name: instance1
      replicas: 1
      dataVolumeClaimSpec:
        accessModes:
        - "ReadWriteOnce"
        resources:
          requests:
            storage: 1Gi
      resources:
        requests:
          cpu: "100m"
          memory: "256Mi"
        limits:
          cpu: "500m"
          memory: "512Mi"
  backups:
    pgbackrest:
      repos:
      - name: repo1
        volume:
          volumeClaimSpec:
            accessModes:
            - "ReadWriteOnce"
            resources:
              requests:
                storage: 1Gi
  proxy:
    pgBouncer:
      replicas: 1
      resources:
        requests:
          cpu: "50m"
          memory: "64Mi"
        limits:
          cpu: "200m"
          memory: "128Mi"
EOF

    log_info "示例 PostgreSQL 集群 'hippo' 已创建"
    log_info "使用以下命令查看集群状态:"
    log_info "  kubectl -n ${NAMESPACE} get postgrescluster"
    log_info "  kubectl -n ${NAMESPACE} get pods"
}

# 获取连接信息
get_connection_info() {
    log_step "获取 PostgreSQL 连接信息..."

    log_info "等待 PostgreSQL 集群就绪..."
    kubectl -n ${NAMESPACE} wait --for=condition=Ready --timeout=300s postgrescluster/hippo || {
        log_warn "集群可能还在初始化中，请稍后检查"
    }

    log_info "PostgreSQL 连接信息:"

    # 获取主机名
    local service_name=$(kubectl -n ${NAMESPACE} get svc -l postgres-operator.crunchydata.com/cluster=hippo,postgres-operator.crunchydata.com/role=master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "$service_name" ]]; then
        log_info "  主机: ${service_name}.${NAMESPACE}.svc.cluster.local"
        log_info "  端口: 5432"
        log_info "  数据库: hippo"

        # 获取密码
        local secret_name=$(kubectl -n ${NAMESPACE} get secret -l postgres-operator.crunchydata.com/cluster=hippo,postgres-operator.crunchydata.com/role=pguser -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

        if [[ -n "$secret_name" ]]; then
            local username=$(kubectl -n ${NAMESPACE} get secret ${secret_name} -o jsonpath='{.data.user}' | base64 -d)
            local password=$(kubectl -n ${NAMESPACE} get secret ${secret_name} -o jsonpath='{.data.password}' | base64 -d)

            log_info "  用户名: ${username}"
            log_info "  密码: ${password}"

            log_info ""
            log_info "连接命令示例:"
            log_info "  kubectl -n ${NAMESPACE} exec -it deployment/hippo-instance1 -- psql -U ${username} -d hippo"
        fi
    else
        log_warn "服务尚未就绪，请稍后使用以下命令检查:"
        log_info "  kubectl -n ${NAMESPACE} get postgrescluster hippo"
        log_info "  kubectl -n ${NAMESPACE} get svc"
        log_info "  kubectl -n ${NAMESPACE} get secret"
    fi
}

# 清理部署
cleanup_deployment() {
    log_step "清理部署..."

    # 删除 PostgreSQL 集群
    kubectl -n ${NAMESPACE} delete postgrescluster --all --ignore-not-found=true

    # 删除 Operator
    kubectl delete -k ./config/default --ignore-not-found=true

    # 删除 CRDs
    kubectl delete -k ./config/crd --ignore-not-found=true

    # 删除命名空间
    kubectl delete namespace ${NAMESPACE} --ignore-not-found=true

    # 清理临时文件
    rm -rf k8s-deploy

    log_info "清理完成"
}

# 显示状态
show_status() {
    log_step "显示当前状态..."

    log_info "命名空间:"
    kubectl get namespace ${NAMESPACE} 2>/dev/null || log_warn "命名空间 ${NAMESPACE} 不存在"

    log_info "CRDs:"
    kubectl get crd | grep postgres-operator || log_warn "未找到 PostgreSQL Operator CRDs"

    log_info "Operator 部署:"
    kubectl -n ${NAMESPACE} get deployment postgres-operator 2>/dev/null || log_warn "Operator 未部署"

    log_info "PostgreSQL 集群:"
    kubectl -n ${NAMESPACE} get postgrescluster 2>/dev/null || log_warn "未找到 PostgreSQL 集群"

    log_info "所有 Pods:"
    kubectl -n ${NAMESPACE} get pods 2>/dev/null || log_warn "命名空间中没有 Pods"
}

# 显示帮助
show_help() {
    cat << EOF
PostgreSQL Operator Kubernetes 部署脚本

用法: $0 [ACTION] [OPTIONS]

ACTION:
  deploy          部署 PostgreSQL Operator (默认)
  deploy-full     部署 Operator 并创建示例集群
  cleanup         清理所有部署
  status          显示当前状态
  connect         获取 PostgreSQL 连接信息
  help            显示此帮助信息

环境变量:
  PGO_NAMESPACE   目标命名空间 (默认: postgres-operator)
  PGO_IMAGE       Operator 镜像 (默认: localhost/postgres-operator:latest)

示例:
  $0 deploy
  PGO_IMAGE=myregistry/postgres-operator:v1.0.0 $0 deploy
  $0 deploy-full
  $0 status
  $0 cleanup

EOF
}

# 主函数
main() {
    case "${ACTION}" in
        deploy)
            log_info "PostgreSQL Operator 部署"
            log_info "========================="
            log_info "命名空间: ${NAMESPACE}"
            log_info "镜像: ${OPERATOR_IMAGE}"
            echo ""

            check_dependencies
            create_namespace
            deploy_crds
            deploy_rbac
            deploy_operator
            verify_deployment

            log_info ""
            log_info "部署完成！"
            log_info "使用 '$0 deploy-full' 来创建示例 PostgreSQL 集群"
            log_info "使用 '$0 status' 查看状态"
            ;;

        deploy-full)
            log_info "PostgreSQL Operator 完整部署"
            log_info "============================="

            check_dependencies
            create_namespace
            deploy_crds
            deploy_rbac
            deploy_operator
            verify_deployment
            create_example_cluster
            get_connection_info

            log_info ""
            log_info "完整部署完成！"
            ;;

        cleanup)
            log_info "清理 PostgreSQL Operator 部署"
            log_info "==============================="

            cleanup_deployment
            ;;

        status)
            log_info "PostgreSQL Operator 状态"
            log_info "========================"

            show_status
            ;;

        connect)
            log_info "PostgreSQL 连接信息"
            log_info "==================="

            get_connection_info
            ;;

        help)
            show_help
            ;;

        *)
            log_error "未知操作: ${ACTION}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main
