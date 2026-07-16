#!/usr/bin/env bash

set -uo pipefail

NAMESPACE="${1:-}"
OUTPUT_DIR="${2:-outputs}"

usage() {
    echo "Usage:"
    echo "  $0 <namespace> [output-directory]"
    echo
    echo "Examples:"
    echo "  $0 example-gitops"
    echo "  $0 example-app ./outputs"
}

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

run_command() {
    echo
    echo "\$ $*"

    if ! "$@" 2>&1; then
        echo "[WARN] Command failed or access was denied."
    fi
}

if [[ -z "$NAMESPACE" ]]; then
    usage
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "[ERROR] kubectl was not found in PATH."
    exit 1
fi

if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "[ERROR] Namespace '$NAMESPACE' does not exist or is not accessible."
    exit 1
fi

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
SAFE_NAMESPACE="$(echo "$NAMESPACE" | tr '/ ' '__')"

mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="${OUTPUT_DIR}/01_namespace_workload_overview_${SAFE_NAMESPACE}_${TIMESTAMP}.txt"

exec > >(tee "$OUTPUT_FILE") 2>&1

CONTEXT="$(kubectl config current-context 2>/dev/null || echo "unknown")"

section "Kubernetes Namespace Workload Overview"

echo "Generated at:       $(date)"
echo "Kubernetes context: $CONTEXT"
echo "Namespace:          $NAMESPACE"
echo "Output file:        $OUTPUT_FILE"

section "1. Namespace"

run_command kubectl get namespace "$NAMESPACE" -o wide

section "2. RBAC Access Check"

for resource in \
    pods \
    deployments \
    replicasets \
    statefulsets \
    daemonsets \
    jobs \
    cronjobs \
    services \
    endpointslices \
    events \
    configmaps \
    secrets \
    persistentvolumeclaims
do
    printf "%-32s " "list $resource:"

    kubectl auth can-i list "$resource" \
        --namespace "$NAMESPACE" 2>/dev/null || echo "unknown"
done

section "3. Workload Controllers"

run_command kubectl get deployments \
    --namespace "$NAMESPACE" \
    -o wide

run_command kubectl get replicasets \
    --namespace "$NAMESPACE" \
    -o wide

run_command kubectl get statefulsets \
    --namespace "$NAMESPACE" \
    -o wide

run_command kubectl get daemonsets \
    --namespace "$NAMESPACE" \
    -o wide

run_command kubectl get jobs \
    --namespace "$NAMESPACE" \
    -o wide

run_command kubectl get cronjobs \
    --namespace "$NAMESPACE" \
    -o wide

section "4. Pods"

run_command kubectl get pods \
    --namespace "$NAMESPACE" \
    -o wide

section "5. Pod Container Status"

run_command kubectl get pods \
    --namespace "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount,WAITING_REASON:.status.containerStatuses[*].state.waiting.reason,LAST_REASON:.status.containerStatuses[*].lastState.terminated.reason,NODE:.spec.nodeName'

section "6. Pods with Potential Problems"

PROBLEM_PODS="$(
    kubectl get pods \
        --namespace "$NAMESPACE" \
        --no-headers 2>/dev/null |
    awk '$3 != "Running" && $3 != "Completed" {print}'
)"

if [[ -n "$PROBLEM_PODS" ]]; then
    echo "$PROBLEM_PODS"
else
    echo "No Pods outside Running or Completed status were detected."
fi

section "7. Pods with Container Restarts"

RESTARTING_PODS="$(
    kubectl get pods \
        --namespace "$NAMESPACE" \
        --no-headers 2>/dev/null |
    awk '$4 != "0" {print}'
)"

if [[ -n "$RESTARTING_PODS" ]]; then
    echo "$RESTARTING_PODS"
else
    echo "No container restarts were detected."
fi

section "8. Warning Events"

if kubectl events --help >/dev/null 2>&1; then
    kubectl events \
        --namespace "$NAMESPACE" \
        --types=Warning \
        2>&1 || echo "[WARN] Could not retrieve Warning events."
else
    kubectl get events \
        --namespace "$NAMESPACE" \
        --field-selector type=Warning \
        --sort-by='.metadata.creationTimestamp' \
        2>&1 || echo "[WARN] Could not retrieve Warning events."
fi

section "9. Recent Namespace Events"

kubectl get events \
    --namespace "$NAMESPACE" \
    --sort-by='.metadata.creationTimestamp' \
    2>&1 |
tail -n 50 || echo "[WARN] Could not retrieve namespace events."

section "10. Services and EndpointSlices"

run_command kubectl get services \
    --namespace "$NAMESPACE" \
    -o wide

run_command kubectl get endpointslices \
    --namespace "$NAMESPACE" \
    -o wide

section "11. Configuration Dependencies"

run_command kubectl get configmaps \
    --namespace "$NAMESPACE"

# Only Secret metadata is displayed.
# Secret values are not decoded or exported.
run_command kubectl get secrets \
    --namespace "$NAMESPACE"

section "12. Persistent Storage"

run_command kubectl get persistentvolumeclaims \
    --namespace "$NAMESPACE" \
    -o wide

section "13. Pod Resource Usage"

if kubectl top pods \
    --namespace "$NAMESPACE" \
    >/dev/null 2>&1
then
    run_command kubectl top pods \
        --namespace "$NAMESPACE" \
        --containers
else
    echo "Pod metrics are unavailable."
    echo "Metrics Server may be unavailable or access may be denied."
fi

section "14. Summary"

POD_COUNT="$(
    kubectl get pods \
        --namespace "$NAMESPACE" \
        --no-headers 2>/dev/null |
    wc -l
)"

RUNNING_COUNT="$(
    kubectl get pods \
        --namespace "$NAMESPACE" \
        --no-headers 2>/dev/null |
    awk '$3 == "Running" {count++} END {print count+0}'
)"

NON_RUNNING_COUNT="$(
    kubectl get pods \
        --namespace "$NAMESPACE" \
        --no-headers 2>/dev/null |
    awk '$3 != "Running" && $3 != "Completed" {count++} END {print count+0}'
)"

NOT_READY_COUNT="$(
    kubectl get pods \
        --namespace "$NAMESPACE" \
        --no-headers 2>/dev/null |
    awk '
        {
            split($2, ready, "/")
            if (ready[1] != ready[2]) {
                count++
            }
        }
        END {
            print count+0
        }
    '
)"

RESTARTING_COUNT="$(
    kubectl get pods \
        --namespace "$NAMESPACE" \
        --no-headers 2>/dev/null |
    awk '$4 != "0" {count++} END {print count+0}'
)"

echo "Total Pods:                       $POD_COUNT"
echo "Running Pods:                     $RUNNING_COUNT"
echo "Pods outside Running/Completed:   $NON_RUNNING_COUNT"
echo "Not-ready Pods:                   $NOT_READY_COUNT"
echo "Pods with container restarts:     $RESTARTING_COUNT"

echo
echo "Namespace overview completed."
echo "Output saved to:"
echo "  $OUTPUT_FILE"

section "End of Kubernetes Namespace Workload Overview"
