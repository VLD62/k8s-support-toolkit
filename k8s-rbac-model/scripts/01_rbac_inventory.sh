#!/usr/bin/env bash

set -uo pipefail

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "${SCRIPT_DIR}")"
OUTPUT_DIR="${1:-${MODULE_DIR}/outputs/rbac_inventory_${TIMESTAMP}}"

mkdir -p "${OUTPUT_DIR}"

LOG_FILE="${OUTPUT_DIR}/00_rbac_inventory_execution.log"
STATUS_FILE="${OUTPUT_DIR}/00_rbac_inventory_status.md"

SUCCESSFUL_CHECKS=0
FAILED_CHECKS=0

log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${message}" | tee -a "${LOG_FILE}"
}

run_check() {
    local description="$1"
    local output_file="$2"
    shift 2

    log "Collecting: ${description}"

    {
        echo "# ${description}"
        echo
        echo "Generated: $(date --iso-8601=seconds)"
        echo
        "$@"
    } >"${OUTPUT_DIR}/${output_file}" 2>&1

    local result=$?

    if [[ ${result} -eq 0 ]]; then
        log "SUCCESS: ${description}"
        SUCCESSFUL_CHECKS=$((SUCCESSFUL_CHECKS + 1))
    else
        log "FAILED OR ACCESS DENIED: ${description}"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi

    return 0
}

if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERROR: kubectl is not installed or is not available in PATH."
    exit 1
fi

log "Starting Kubernetes RBAC inventory"
log "Output directory: ${OUTPUT_DIR}"

run_check \
    "Kubernetes client and server version" \
    "01_kubernetes_version.txt" \
    kubectl version

run_check \
    "Current Kubernetes context" \
    "02_current_context.txt" \
    kubectl config current-context

run_check \
    "Current Kubernetes user information" \
    "03_current_user.txt" \
    kubectl auth whoami

run_check \
    "Available Kubernetes contexts" \
    "04_available_contexts.txt" \
    kubectl config get-contexts

run_check \
    "Current namespace configuration" \
    "05_current_namespace.txt" \
    bash -c '
        namespace="$(kubectl config view \
            --minify \
            --output "jsonpath={..namespace}" 2>/dev/null)"

        if [[ -z "${namespace}" ]]; then
            namespace="default"
        fi

        echo "${namespace}"
    '

run_check \
    "Namespaces visible to the current user" \
    "06_namespaces.txt" \
    kubectl get namespaces -o wide

run_check \
    "ClusterRoles summary" \
    "07_clusterroles.txt" \
    kubectl get clusterroles \
        -o custom-columns='NAME:.metadata.name,CREATED:.metadata.creationTimestamp'

run_check \
    "ClusterRoleBindings summary" \
    "08_clusterrolebindings.txt" \
    kubectl get clusterrolebindings \
        -o custom-columns='NAME:.metadata.name,ROLE:.roleRef.name,SUBJECT-KINDS:.subjects[*].kind,SUBJECTS:.subjects[*].name,CREATED:.metadata.creationTimestamp'

run_check \
    "Namespace Roles summary" \
    "09_roles_all_namespaces.txt" \
    kubectl get roles \
        --all-namespaces \
        -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,CREATED:.metadata.creationTimestamp'

run_check \
    "Namespace RoleBindings summary" \
    "10_rolebindings_all_namespaces.txt" \
    kubectl get rolebindings \
        --all-namespaces \
        -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,ROLE-KIND:.roleRef.kind,ROLE:.roleRef.name,SUBJECT-KINDS:.subjects[*].kind,SUBJECTS:.subjects[*].name,CREATED:.metadata.creationTimestamp'

run_check \
    "Complete ClusterRole definitions" \
    "11_clusterroles.yaml" \
    kubectl get clusterroles -o yaml

run_check \
    "Complete ClusterRoleBinding definitions" \
    "12_clusterrolebindings.yaml" \
    kubectl get clusterrolebindings -o yaml

run_check \
    "Complete namespace Role definitions" \
    "13_roles_all_namespaces.yaml" \
    kubectl get roles --all-namespaces -o yaml

run_check \
    "Complete namespace RoleBinding definitions" \
    "14_rolebindings_all_namespaces.yaml" \
    kubectl get rolebindings --all-namespaces -o yaml

run_check \
    "Effective permissions in the current namespace" \
    "15_current_namespace_permissions.txt" \
    kubectl auth can-i --list

run_check \
    "General cluster-level permission checks" \
    "16_cluster_permission_checks.txt" \
    bash -c '
        checks=(
            "get namespaces"
            "list nodes"
            "get nodes"
            "list clusterroles.rbac.authorization.k8s.io"
            "list clusterrolebindings.rbac.authorization.k8s.io"
            "create namespaces"
            "delete namespaces"
        )

        for check in "${checks[@]}"; do
            printf "%-70s" "kubectl auth can-i ${check}"
            kubectl auth can-i ${check}
        done
    '

run_check \
    "Common Kubernetes support permission checks" \
    "17_support_permission_checks.txt" \
    bash -c '
        checks=(
            "get pods --all-namespaces"
            "list pods --all-namespaces"
            "watch pods --all-namespaces"
            "get pods/log --all-namespaces"
            "create pods/exec --all-namespaces"
            "get deployments.apps --all-namespaces"
            "patch deployments.apps --all-namespaces"
            "update deployments.apps --all-namespaces"
            "get statefulsets.apps --all-namespaces"
            "patch statefulsets.apps --all-namespaces"
            "get daemonsets.apps --all-namespaces"
            "get jobs.batch --all-namespaces"
            "get cronjobs.batch --all-namespaces"
            "get services --all-namespaces"
            "get endpoints --all-namespaces"
            "get ingresses.networking.k8s.io --all-namespaces"
            "get events --all-namespaces"
            "get configmaps --all-namespaces"
            "get secrets --all-namespaces"
            "get persistentvolumeclaims --all-namespaces"
            "get persistentvolumes"
            "get storageclasses.storage.k8s.io"
        )

        for check in "${checks[@]}"; do
            printf "%-90s" "kubectl auth can-i ${check}"
            kubectl auth can-i ${check}
        done
    '

run_check \
    "Bindings to cluster-admin" \
    "18_cluster_admin_bindings.txt" \
    bash -c '
        kubectl get clusterrolebindings \
            -o jsonpath="{range .items[?(@.roleRef.name==\"cluster-admin\")]}Binding: {.metadata.name}{\"\n\"}Subjects:{\"\n\"}{range .subjects[*]}  - Kind: {.kind}, Name: {.name}, Namespace: {.namespace}{\"\n\"}{end}{\"\n\"}{end}"
    '

run_check \
    "ServiceAccounts referenced by RoleBindings and ClusterRoleBindings" \
    "19_bound_service_accounts.txt" \
    bash -c '
        echo "ClusterRoleBinding ServiceAccounts"
        echo "=================================="

        kubectl get clusterrolebindings \
            -o jsonpath="{range .items[*]}{.metadata.name}{\"\t\"}{.roleRef.name}{\"\t\"}{range .subjects[?(@.kind==\"ServiceAccount\")]}{.namespace}/{.name}{\" \"}{end}{\"\n\"}{end}"

        echo
        echo "RoleBinding ServiceAccounts"
        echo "==========================="

        kubectl get rolebindings --all-namespaces \
            -o jsonpath="{range .items[*]}{.metadata.namespace}{\"\t\"}{.metadata.name}{\"\t\"}{.roleRef.kind}/{.roleRef.name}{\"\t\"}{range .subjects[?(@.kind==\"ServiceAccount\")]}{.namespace}/{.name}{\" \"}{end}{\"\n\"}{end}"
    '

{
    echo "# Kubernetes RBAC Inventory Status"
    echo
    echo "- Generated: $(date --iso-8601=seconds)"
    echo "- Kubernetes context: $(kubectl config current-context 2>/dev/null || echo unavailable)"
    echo "- Successful checks: ${SUCCESSFUL_CHECKS}"
    echo "- Failed or access-denied checks: ${FAILED_CHECKS}"
    echo "- Output directory: \`${OUTPUT_DIR}\`"
    echo
    echo "## Security"
    echo
    echo "The inventory does not request Secret values, service-account tokens, client certificates, or kubeconfig credentials."
    echo
    echo "RBAC outputs may contain internal usernames, groups, and service-account names and should therefore be handled as operationally sensitive information."
} >"${STATUS_FILE}"

log "RBAC inventory completed"
log "Successful checks: ${SUCCESSFUL_CHECKS}"
log "Failed or access-denied checks: ${FAILED_CHECKS}"
log "Status file: ${STATUS_FILE}"

echo
echo "RBAC inventory completed."
echo "Results: ${OUTPUT_DIR}"