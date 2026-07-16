#!/usr/bin/env bash

set -uo pipefail

NAMESPACE="${1:-}"
POD_NAME="${2:-}"
OUTPUT_DIR="${3:-outputs}"
LOG_TAIL="${4:-200}"

usage() {
    echo "Usage:"
    echo "  $0 <namespace> <pod-name> [output-directory] [log-tail]"
    echo
    echo "Examples:"
    echo "  $0 example-app example-worker-0"
    echo "  $0 example-app example-api-7d9f8c6b5-x2abc"
    echo "  $0 example-gitops example-gitops-server-7d9f8c6b5-y3def ./outputs 300"
}

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

subsection() {
    echo
    echo "------------------------------------------------------------"
    echo "$1"
    echo "------------------------------------------------------------"
}

run_command() {
    echo
    echo "\$ $*"

    if ! "$@" 2>&1; then
        echo "[WARN] Command failed, timed out, or access was denied."
    fi
}

safe_jsonpath() {
    local expression="$1"

    kubectl get pod "$POD_NAME" \
        --namespace "$NAMESPACE" \
        -o "jsonpath=${expression}" 2>/dev/null || true
}

if [[ -z "$NAMESPACE" || -z "$POD_NAME" ]]; then
    usage
    exit 1
fi

if ! [[ "$LOG_TAIL" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] log-tail must be a non-negative integer."
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

if ! kubectl get pod "$POD_NAME" \
    --namespace "$NAMESPACE" >/dev/null 2>&1
then
    echo "[ERROR] Pod '$POD_NAME' was not found in namespace '$NAMESPACE'."
    exit 1
fi

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
SAFE_NAMESPACE="$(echo "$NAMESPACE" | tr '/ ' '__')"
SAFE_POD="$(echo "$POD_NAME" | tr '/ ' '__')"

mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="${OUTPUT_DIR}/03_pod_diagnostics_${SAFE_NAMESPACE}_${SAFE_POD}_${TIMESTAMP}.txt"

exec > >(tee "$OUTPUT_FILE") 2>&1

CONTEXT="$(kubectl config current-context 2>/dev/null || echo "unknown")"
NODE_NAME="$(safe_jsonpath '{.spec.nodeName}')"

mapfile -t INIT_CONTAINERS < <(
    kubectl get pod "$POD_NAME" \
        --namespace "$NAMESPACE" \
        -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null |
    tr ' ' '\n' |
    sed '/^$/d'
)

mapfile -t APP_CONTAINERS < <(
    kubectl get pod "$POD_NAME" \
        --namespace "$NAMESPACE" \
        -o jsonpath='{.spec.containers[*].name}' 2>/dev/null |
    tr ' ' '\n' |
    sed '/^$/d'
)

section "Kubernetes Pod Diagnostics"

echo "Generated at:       $(date)"
echo "Kubernetes context: $CONTEXT"
echo "Namespace:          $NAMESPACE"
echo "Pod:                $POD_NAME"
echo "Node:               ${NODE_NAME:-<not assigned>}"
echo "Log tail:           $LOG_TAIL lines per container"
echo "Output file:        $OUTPUT_FILE"

section "1. RBAC Access Check"

printf "%-34s " "get pod:"
kubectl auth can-i get pods \
    --namespace "$NAMESPACE" 2>/dev/null || echo "unknown"

printf "%-34s " "get pod logs:"
kubectl auth can-i get pods \
    --subresource=log \
    --namespace "$NAMESPACE" 2>/dev/null || echo "unknown"

printf "%-34s " "list events:"
kubectl auth can-i list events \
    --namespace "$NAMESPACE" 2>/dev/null || echo "unknown"

if [[ -n "$NODE_NAME" ]]; then
    printf "%-34s " "get assigned node:"
    kubectl auth can-i get nodes 2>/dev/null || echo "unknown"
fi

section "2. Pod Overview"

run_command kubectl get pod "$POD_NAME" \
    --namespace "$NAMESPACE" \
    -o wide

run_command kubectl get pod "$POD_NAME" \
    --namespace "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount,INIT_RESTARTS:.status.initContainerStatuses[*].restartCount,POD_IP:.status.podIP,HOST_IP:.status.hostIP,NODE:.spec.nodeName,QOS:.status.qosClass,START_TIME:.status.startTime'

section "3. Ownership and Scheduling"

run_command kubectl get pod "$POD_NAME" \
    --namespace "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,OWNER_KIND:.metadata.ownerReferences[0].kind,OWNER_NAME:.metadata.ownerReferences[0].name,SERVICE_ACCOUNT:.spec.serviceAccountName,PRIORITY_CLASS:.spec.priorityClassName,RESTART_POLICY:.spec.restartPolicy,NODE_SELECTOR:.spec.nodeSelector'

echo
echo "Labels:"
kubectl get pod "$POD_NAME" \
    --namespace "$NAMESPACE" \
    --show-labels 2>&1 || echo "[WARN] Could not retrieve Pod labels."

section "4. Pod Conditions"

run_command kubectl get pod "$POD_NAME" \
    --namespace "$NAMESPACE" \
    -o custom-columns='TYPE:.status.conditions[*].type,STATUS:.status.conditions[*].status,REASON:.status.conditions[*].reason,MESSAGE:.status.conditions[*].message,LAST_TRANSITION:.status.conditions[*].lastTransitionTime'

section "5. Container Inventory"

subsection "Init Containers"

if [[ "${#INIT_CONTAINERS[@]}" -eq 0 ]]; then
    echo "No init containers are defined."
else
    kubectl get pod "$POD_NAME" \
        --namespace "$NAMESPACE" \
        -o go-template='{{range .spec.initContainers}}Name: {{.name}}
Image: {{.image}}
Restart policy: {{if .restartPolicy}}{{.restartPolicy}}{{else}}<not set>{{end}}

{{end}}' \
        2>&1 || echo "[WARN] Could not retrieve init-container inventory."
fi

subsection "Application Containers"

if [[ "${#APP_CONTAINERS[@]}" -eq 0 ]]; then
    echo "No application containers are defined."
else
    kubectl get pod "$POD_NAME" \
        --namespace "$NAMESPACE" \
        -o go-template='{{range .spec.containers}}{{printf "Name: %s\nImage: %s\nImage pull policy: %s\n\n" .name .image .imagePullPolicy}}{{end}}' \
        2>&1 || echo "[WARN] Could not retrieve application-container inventory."
fi

section "6. Init Container States"

if [[ "${#INIT_CONTAINERS[@]}" -eq 0 ]]; then
    echo "No init containers are defined."
else
    kubectl get pod "$POD_NAME" \
        --namespace "$NAMESPACE" \
        -o go-template='
{{range .status.initContainerStatuses}}
Name: {{.name}}
Ready: {{.ready}}
Started: {{.started}}
Restart count: {{.restartCount}}
{{if .state.running}}Current state: Running
Started at: {{.state.running.startedAt}}
{{end}}{{if .state.waiting}}Current state: Waiting
Reason: {{.state.waiting.reason}}
Message: {{.state.waiting.message}}
{{end}}{{if .state.terminated}}Current state: Terminated
Reason: {{.state.terminated.reason}}
Exit code: {{.state.terminated.exitCode}}
Signal: {{.state.terminated.signal}}
Started at: {{.state.terminated.startedAt}}
Finished at: {{.state.terminated.finishedAt}}
Message: {{.state.terminated.message}}
{{end}}{{if .lastState.terminated}}Previous state: Terminated
Previous reason: {{.lastState.terminated.reason}}
Previous exit code: {{.lastState.terminated.exitCode}}
Previous signal: {{.lastState.terminated.signal}}
Previous started at: {{.lastState.terminated.startedAt}}
Previous finished at: {{.lastState.terminated.finishedAt}}
Previous message: {{.lastState.terminated.message}}
{{end}}
---
{{end}}' 2>&1 || echo "[WARN] Could not retrieve init-container states."
fi

section "7. Application Container States"

kubectl get pod "$POD_NAME" \
    --namespace "$NAMESPACE" \
    -o go-template='
{{range .status.containerStatuses}}
Name: {{.name}}
Ready: {{.ready}}
Started: {{.started}}
Restart count: {{.restartCount}}
Container ID: {{.containerID}}
Image ID: {{.imageID}}
{{if .state.running}}Current state: Running
Started at: {{.state.running.startedAt}}
{{end}}{{if .state.waiting}}Current state: Waiting
Reason: {{.state.waiting.reason}}
Message: {{.state.waiting.message}}
{{end}}{{if .state.terminated}}Current state: Terminated
Reason: {{.state.terminated.reason}}
Exit code: {{.state.terminated.exitCode}}
Signal: {{.state.terminated.signal}}
Started at: {{.state.terminated.startedAt}}
Finished at: {{.state.terminated.finishedAt}}
Message: {{.state.terminated.message}}
{{end}}{{if .lastState.terminated}}Previous state: Terminated
Previous reason: {{.lastState.terminated.reason}}
Previous exit code: {{.lastState.terminated.exitCode}}
Previous signal: {{.lastState.terminated.signal}}
Previous started at: {{.lastState.terminated.startedAt}}
Previous finished at: {{.lastState.terminated.finishedAt}}
Previous message: {{.lastState.terminated.message}}
{{end}}
---
{{end}}' 2>&1 || echo "[WARN] Could not retrieve application-container states."

section "8. Resource Requests, Limits, and Probes"

subsection "Init Containers"

if [[ "${#INIT_CONTAINERS[@]}" -eq 0 ]]; then
    echo "No init containers are defined."
else
    kubectl get pod "$POD_NAME" \
        --namespace "$NAMESPACE" \
        -o go-template='
{{range .spec.initContainers}}
Container: {{.name}}
CPU request: {{with .resources.requests}}{{index . "cpu"}}{{else}}<none>{{end}}
Memory request: {{with .resources.requests}}{{index . "memory"}}{{else}}<none>{{end}}
CPU limit: {{with .resources.limits}}{{index . "cpu"}}{{else}}<none>{{end}}
Memory limit: {{with .resources.limits}}{{index . "memory"}}{{else}}<none>{{end}}
Liveness probe: {{if .livenessProbe}}configured{{else}}<none>{{end}}
Readiness probe: {{if .readinessProbe}}configured{{else}}<none>{{end}}
Startup probe: {{if .startupProbe}}configured{{else}}<none>{{end}}
---
{{end}}' 2>&1 || echo "[WARN] Could not retrieve init-container resources."
fi

subsection "Application Containers"

kubectl get pod "$POD_NAME" \
    --namespace "$NAMESPACE" \
    -o go-template='
{{range .spec.containers}}
Container: {{.name}}
CPU request: {{with .resources.requests}}{{index . "cpu"}}{{else}}<none>{{end}}
Memory request: {{with .resources.requests}}{{index . "memory"}}{{else}}<none>{{end}}
CPU limit: {{with .resources.limits}}{{index . "cpu"}}{{else}}<none>{{end}}
Memory limit: {{with .resources.limits}}{{index . "memory"}}{{else}}<none>{{end}}
Liveness probe: {{if .livenessProbe}}configured{{else}}<none>{{end}}
Readiness probe: {{if .readinessProbe}}configured{{else}}<none>{{end}}
Startup probe: {{if .startupProbe}}configured{{else}}<none>{{end}}
---
{{end}}' 2>&1 || echo "[WARN] Could not retrieve application-container resources."

section "9. Configuration References"

echo "The following output contains reference names only."
echo "Secret values are not decoded or exported."

kubectl get pod "$POD_NAME" \
    --namespace "$NAMESPACE" \
    -o go-template='
{{range .spec.initContainers}}
Init container: {{.name}}
{{range .envFrom}}{{with .configMapRef}}  envFrom ConfigMap: {{.name}} (optional={{.optional}})
{{end}}{{with .secretRef}}  envFrom Secret: {{.name}} (optional={{.optional}})
{{end}}{{end}}{{range .env}}{{with .valueFrom}}{{with .configMapKeyRef}}  ConfigMap reference: {{.name}} key={{.key}} optional={{.optional}}
{{end}}{{with .secretKeyRef}}  Secret reference: {{.name}} key={{.key}} optional={{.optional}}
{{end}}{{end}}{{end}}
{{end}}
{{range .spec.containers}}
Application container: {{.name}}
{{range .envFrom}}{{with .configMapRef}}  envFrom ConfigMap: {{.name}} (optional={{.optional}})
{{end}}{{with .secretRef}}  envFrom Secret: {{.name}} (optional={{.optional}})
{{end}}{{end}}{{range .env}}{{with .valueFrom}}{{with .configMapKeyRef}}  ConfigMap reference: {{.name}} key={{.key}} optional={{.optional}}
{{end}}{{with .secretKeyRef}}  Secret reference: {{.name}} key={{.key}} optional={{.optional}}
{{end}}{{end}}{{end}}
{{end}}' 2>&1 || echo "[WARN] Could not retrieve configuration references."

section "10. Volumes and Volume Mounts"

subsection "Volumes"

kubectl get pod "$POD_NAME" \
    --namespace "$NAMESPACE" \
    -o go-template='
{{range .spec.volumes}}
Volume: {{.name}}
{{with .configMap}}  Type: ConfigMap
  Name: {{.name}}
  Optional: {{.optional}}
{{end}}{{with .secret}}  Type: Secret
  Name: {{.secretName}}
  Optional: {{.optional}}
{{end}}{{with .persistentVolumeClaim}}  Type: PersistentVolumeClaim
  Claim: {{.claimName}}
  Read only: {{.readOnly}}
{{end}}{{if ne .emptyDir nil}}  Type: EmptyDir
  Medium: {{if .emptyDir.medium}}{{.emptyDir.medium}}{{else}}<default>{{end}}
  Size limit: {{if .emptyDir.sizeLimit}}{{.emptyDir.sizeLimit}}{{else}}<none>{{end}}
{{end}}{{with .projected}}  Type: Projected
{{end}}{{with .hostPath}}  Type: HostPath
  Path: {{.path}}
{{end}}
---
{{end}}' 2>&1 || echo "[WARN] Could not retrieve Pod volumes."

subsection "Container Mounts"

kubectl get pod "$POD_NAME" \
    --namespace "$NAMESPACE" \
    -o go-template='
{{range .spec.initContainers}}
Init container: {{.name}}
{{range .volumeMounts}}  {{.name}} -> {{.mountPath}} (readOnly={{.readOnly}}, subPath={{.subPath}})
{{end}}{{end}}
{{range .spec.containers}}
Application container: {{.name}}
{{range .volumeMounts}}  {{.name}} -> {{.mountPath}} (readOnly={{.readOnly}}, subPath={{.subPath}})
{{end}}{{end}}' 2>&1 || echo "[WARN] Could not retrieve volume mounts."

section "11. Pod Description"

echo "[INFO] kubectl describe may include literal non-secret environment values."
run_command kubectl describe pod "$POD_NAME" \
    --namespace "$NAMESPACE"

section "12. Pod Events"

kubectl get events \
    --namespace "$NAMESPACE" \
    --field-selector "involvedObject.kind=Pod,involvedObject.name=${POD_NAME}" \
    --sort-by='.metadata.creationTimestamp' \
    2>&1 || echo "[WARN] Could not retrieve Pod events."

section "13. Current Init Container Logs"

if [[ "${#INIT_CONTAINERS[@]}" -eq 0 ]]; then
    echo "No init containers are defined."
else
    for container_name in "${INIT_CONTAINERS[@]}"; do
        subsection "Init container: $container_name"

        kubectl logs "$POD_NAME" \
            --namespace "$NAMESPACE" \
            --container "$container_name" \
            --tail="$LOG_TAIL" \
            --timestamps=true \
            --request-timeout=20s \
            2>&1 || echo "[WARN] Current logs are unavailable for init container '$container_name'."
    done
fi

section "14. Previous Init Container Logs"

PREVIOUS_INIT_LOGS_ATTEMPTED=0

for container_name in "${INIT_CONTAINERS[@]}"; do
    restart_count="$(
        kubectl get pod "$POD_NAME" \
            --namespace "$NAMESPACE" \
            -o "jsonpath={.status.initContainerStatuses[?(@.name=='${container_name}')].restartCount}" \
            2>/dev/null || echo "0"
    )"

    restart_count="${restart_count:-0}"

    if [[ "$restart_count" =~ ^[0-9]+$ ]] && [[ "$restart_count" -gt 0 ]]; then
        PREVIOUS_INIT_LOGS_ATTEMPTED=$((PREVIOUS_INIT_LOGS_ATTEMPTED + 1))

        subsection "Previous init container: $container_name"

        kubectl logs "$POD_NAME" \
            --namespace "$NAMESPACE" \
            --container "$container_name" \
            --previous \
            --tail="$LOG_TAIL" \
            --timestamps=true \
            --request-timeout=20s \
            2>&1 || echo "[WARN] Previous logs are unavailable for init container '$container_name'."
    fi
done

if [[ "$PREVIOUS_INIT_LOGS_ATTEMPTED" -eq 0 ]]; then
    echo "No init container has a restart count greater than zero."
fi

section "15. Current Application Container Logs"

for container_name in "${APP_CONTAINERS[@]}"; do
    subsection "Application container: $container_name"

    kubectl logs "$POD_NAME" \
        --namespace "$NAMESPACE" \
        --container "$container_name" \
        --tail="$LOG_TAIL" \
        --timestamps=true \
        --request-timeout=20s \
        2>&1 || echo "[WARN] Current logs are unavailable for application container '$container_name'."
done

section "16. Previous Application Container Logs"

PREVIOUS_APP_LOGS_ATTEMPTED=0

for container_name in "${APP_CONTAINERS[@]}"; do
    restart_count="$(
        kubectl get pod "$POD_NAME" \
            --namespace "$NAMESPACE" \
            -o "jsonpath={.status.containerStatuses[?(@.name=='${container_name}')].restartCount}" \
            2>/dev/null || echo "0"
    )"

    restart_count="${restart_count:-0}"

    if [[ "$restart_count" =~ ^[0-9]+$ ]] && [[ "$restart_count" -gt 0 ]]; then
        PREVIOUS_APP_LOGS_ATTEMPTED=$((PREVIOUS_APP_LOGS_ATTEMPTED + 1))

        subsection "Previous application container: $container_name"

        kubectl logs "$POD_NAME" \
            --namespace "$NAMESPACE" \
            --container "$container_name" \
            --previous \
            --tail="$LOG_TAIL" \
            --timestamps=true \
            --request-timeout=20s \
            2>&1 || echo "[WARN] Previous logs are unavailable for application container '$container_name'."
    fi
done

if [[ "$PREVIOUS_APP_LOGS_ATTEMPTED" -eq 0 ]]; then
    echo "No application container has a restart count greater than zero."
fi

section "17. Current Resource Usage"

if kubectl top pod "$POD_NAME" \
    --namespace "$NAMESPACE" >/dev/null 2>&1
then
    run_command kubectl top pod "$POD_NAME" \
        --namespace "$NAMESPACE" \
        --containers
else
    echo "Pod metrics are unavailable."
    echo "Metrics Server may be unavailable or access may be denied."
fi

section "18. Assigned Node Overview"

if [[ -z "$NODE_NAME" ]]; then
    echo "The Pod has not been assigned to a node."
elif kubectl auth can-i get nodes 2>/dev/null | grep -qx "yes"; then
    run_command kubectl get node "$NODE_NAME" \
        -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[?(@.type=="Ready")].status,READY_REASON:.status.conditions[?(@.type=="Ready")].reason,MEMORY_PRESSURE:.status.conditions[?(@.type=="MemoryPressure")].status,DISK_PRESSURE:.status.conditions[?(@.type=="DiskPressure")].status,PID_PRESSURE:.status.conditions[?(@.type=="PIDPressure")].status,UNSCHEDULABLE:.spec.unschedulable,KUBELET:.status.nodeInfo.kubeletVersion'

    if kubectl top node "$NODE_NAME" >/dev/null 2>&1; then
        run_command kubectl top node "$NODE_NAME"
    else
        echo "Node metrics are unavailable."
    fi
else
    echo "Node details were skipped because access is not available."
fi

section "19. Diagnostic Summary"

PHASE="$(safe_jsonpath '{.status.phase}')"

READY_COUNT="$(
    safe_jsonpath '{.status.containerStatuses[*].ready}' |
    tr ' ' '\n' |
    awk '$1 == "true" {count++} END {print count+0}'
)"

APP_CONTAINER_COUNT="${#APP_CONTAINERS[@]}"
INIT_CONTAINER_COUNT="${#INIT_CONTAINERS[@]}"

APP_RESTARTS="$(
    safe_jsonpath '{.status.containerStatuses[*].restartCount}' |
    tr ' ' '\n' |
    awk '/^[0-9]+$/ {total += $1} END {print total+0}'
)"

INIT_RESTARTS="$(
    safe_jsonpath '{.status.initContainerStatuses[*].restartCount}' |
    tr ' ' '\n' |
    awk '/^[0-9]+$/ {total += $1} END {print total+0}'
)"

WAITING_REASONS="$(
    safe_jsonpath '{.status.containerStatuses[*].state.waiting.reason}' |
    xargs 2>/dev/null || true
)"

LAST_TERMINATION_REASONS="$(
    safe_jsonpath '{.status.containerStatuses[*].lastState.terminated.reason}' |
    xargs 2>/dev/null || true
)"

echo "Pod phase:                         ${PHASE:-unknown}"
echo "Application containers:           $APP_CONTAINER_COUNT"
echo "Ready application containers:     $READY_COUNT"
echo "Init containers:                  $INIT_CONTAINER_COUNT"
echo "Application-container restarts:   $APP_RESTARTS"
echo "Init-container restarts:          $INIT_RESTARTS"
echo "Current waiting reasons:          ${WAITING_REASONS:-<none>}"
echo "Previous termination reasons:     ${LAST_TERMINATION_REASONS:-<none>}"
echo "Previous app logs attempted:       $PREVIOUS_APP_LOGS_ATTEMPTED"
echo "Previous init logs attempted:      $PREVIOUS_INIT_LOGS_ATTEMPTED"

echo
echo "Pod diagnostics completed."
echo "Output saved to:"
echo "  $OUTPUT_FILE"

section "End of Kubernetes Pod Diagnostics"