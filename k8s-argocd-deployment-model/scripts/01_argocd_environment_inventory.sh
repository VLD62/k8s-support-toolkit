#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLSET_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
OUTPUT_DIR="${OUTPUT_DIR:-${TOOLSET_DIR}/output}"
OUTPUT_FILE="${OUTPUT_DIR}/01_argocd_environment_inventory_${TIMESTAMP}.txt"

mkdir -p "${OUTPUT_DIR}"

exec > >(tee "${OUTPUT_FILE}") 2>&1

print_header() {
    local title="$1"

    echo
    echo "======================================================================"
    echo "${title}"
    echo "======================================================================"
}

run_command() {
    local title="$1"
    shift

    print_header "${title}"

    if "$@"; then
        return 0
    else
        local exit_code=$?
        echo
        echo "[WARNING] Command failed or access is not permitted."
        echo "[WARNING] Exit code: ${exit_code}"
        return 0
    fi
}

run_shell_command() {
    local title="$1"
    local command="$2"

    print_header "${title}"

    if bash -c "${command}"; then
        return 0
    else
        local exit_code=$?
        echo
        echo "[WARNING] Command failed or access is not permitted."
        echo "[WARNING] Exit code: ${exit_code}"
        return 0
    fi
}

detect_argocd_namespace() {
    local namespace

    namespace="$(
        kubectl get deployments --all-namespaces \
            -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' \
            2>/dev/null |
            awk '$2 == "argocd-server" {print $1; exit}'
    )"

    if [[ -z "${namespace}" ]]; then
        namespace="$(
            kubectl get namespaces \
                -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
                2>/dev/null |
                grep -E '^(argocd|argo-cd)$' |
                head -n 1
        )"
    fi

    echo "${namespace}"
}

print_header "Argo CD Environment Inventory"

echo "Collection timestamp: $(date --iso-8601=seconds)"
echo "Output file: ${OUTPUT_FILE}"
echo "Hostname: $(hostname)"
echo "User: $(whoami)"

run_command \
    "Current Kubernetes Context" \
    kubectl config current-context

run_command \
    "Kubernetes Client and Server Versions" \
    kubectl version

run_command \
    "Cluster Information" \
    kubectl cluster-info

run_command \
    "Authenticated Kubernetes User" \
    kubectl auth whoami

run_shell_command \
    "Namespaces Potentially Related to Argo CD" \
    "kubectl get namespaces 2>&1 | grep -Ei 'NAME|argocd|argo-cd' || true"

ARGOCD_NAMESPACE="$(detect_argocd_namespace)"

print_header "Detected Argo CD Namespace"

if [[ -n "${ARGOCD_NAMESPACE}" ]]; then
    echo "${ARGOCD_NAMESPACE}"
else
    echo "[WARNING] Argo CD namespace could not be detected automatically."
    echo "[WARNING] The remaining namespace-specific checks will be skipped."
fi

run_shell_command \
    "Argo CD Custom Resource Definitions" \
    "kubectl get crd 2>&1 | grep -E 'NAME|argoproj.io' || true"

run_shell_command \
    "Argo CD API Resources" \
    "kubectl api-resources 2>&1 | grep -Ei 'applicationsets|applications|appprojects|argoproj' || true"

run_command \
    "Access Check: List Argo CD Applications" \
    kubectl auth can-i list applications.argoproj.io --all-namespaces

run_command \
    "Access Check: List Argo CD Projects" \
    kubectl auth can-i list appprojects.argoproj.io --all-namespaces

run_command \
    "Access Check: List Argo CD ApplicationSets" \
    kubectl auth can-i list applicationsets.argoproj.io --all-namespaces

run_command \
    "Argo CD Applications Across All Namespaces" \
    kubectl get applications.argoproj.io --all-namespaces -o wide

run_command \
    "Argo CD Projects Across All Namespaces" \
    kubectl get appprojects.argoproj.io --all-namespaces

run_command \
    "Argo CD ApplicationSets Across All Namespaces" \
    kubectl get applicationsets.argoproj.io --all-namespaces -o wide

if [[ -n "${ARGOCD_NAMESPACE}" ]]; then
    run_command \
        "Argo CD Workloads" \
        kubectl get deployments,statefulsets,daemonsets \
            --namespace "${ARGOCD_NAMESPACE}" \
            -o wide

    run_command \
        "Argo CD Pods" \
        kubectl get pods \
            --namespace "${ARGOCD_NAMESPACE}" \
            -o wide

    run_command \
        "Argo CD Services" \
        kubectl get services \
            --namespace "${ARGOCD_NAMESPACE}" \
            -o wide

    run_command \
        "Argo CD Ingress Resources" \
        kubectl get ingress \
            --namespace "${ARGOCD_NAMESPACE}" \
            -o wide

    run_command \
        "Argo CD Container Images" \
        kubectl get deployments,statefulsets \
            --namespace "${ARGOCD_NAMESPACE}" \
            -o jsonpath='{range .items[*]}{"\n"}{.kind}{"/"}{.metadata.name}{"\n"}{range .spec.template.spec.containers[*]}{"  "}{.name}{": "}{.image}{"\n"}{end}{end}'

    run_command \
        "Argo CD Configuration ConfigMaps" \
        kubectl get configmaps \
            --namespace "${ARGOCD_NAMESPACE}"

    run_command \
        "Argo CD Secrets Inventory" \
        kubectl get secrets \
            --namespace "${ARGOCD_NAMESPACE}"
fi

run_shell_command \
    "Traefik IngressRoutes Related to Argo CD" \
    "if kubectl api-resources --api-group=traefik.io 2>/dev/null |
        grep -q '^ingressroutes'; then
            kubectl get ingressroutes.traefik.io --all-namespaces -o wide 2>&1 |
                grep -Ei 'NAMESPACE|argocd|argo-cd' || true
     elif kubectl api-resources --api-group=traefik.containo.us 2>/dev/null |
        grep -q '^ingressroutes'; then
            kubectl get ingressroutes.traefik.containo.us --all-namespaces -o wide 2>&1 |
                grep -Ei 'NAMESPACE|argocd|argo-cd' || true
     else
            echo 'Traefik IngressRoute API resource is not available.'
     fi"

print_header "Inventory Summary"

echo "Detected Argo CD namespace: ${ARGOCD_NAMESPACE:-not detected}"
echo "Inventory completed successfully."
echo "Generated output:"
echo "${OUTPUT_FILE}"
