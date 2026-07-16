#!/usr/bin/env bash

set -uo pipefail

NAMESPACE="${1:-}"
SERVICE_NAME="${2:-}"
OUTPUT_DIR="${3:-outputs}"

usage() {
    echo "Usage:"
    echo "  $0 <namespace> <service-name> [output-directory]"
    echo
    echo "Examples:"
    echo "  $0 example-app example-api"
    echo "  $0 example-app example-worker"
    echo "  $0 example-gitops example-gitops-server"
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
        echo "[WARN] Command failed or access was denied."
    fi
}

safe_jsonpath() {
    local resource="$1"
    local name="$2"
    local expression="$3"

    kubectl get "$resource" "$name" \
        --namespace "$NAMESPACE" \
        -o "jsonpath=${expression}" 2>/dev/null || true
}

if [[ -z "$NAMESPACE" || -z "$SERVICE_NAME" ]]; then
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

if ! kubectl get service "$SERVICE_NAME" \
    --namespace "$NAMESPACE" >/dev/null 2>&1
then
    echo "[ERROR] Service '$SERVICE_NAME' was not found in namespace '$NAMESPACE'."
    exit 1
fi

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
SAFE_NAMESPACE="$(echo "$NAMESPACE" | tr '/ ' '__')"
SAFE_SERVICE="$(echo "$SERVICE_NAME" | tr '/ ' '__')"

mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="${OUTPUT_DIR}/04_service_dependency_check_${SAFE_NAMESPACE}_${SAFE_SERVICE}_${TIMESTAMP}.txt"

exec > >(tee "$OUTPUT_FILE") 2>&1

CONTEXT="$(kubectl config current-context 2>/dev/null || echo "unknown")"

SERVICE_TYPE="$(safe_jsonpath service "$SERVICE_NAME" '{.spec.type}')"
CLUSTER_IP="$(safe_jsonpath service "$SERVICE_NAME" '{.spec.clusterIP}')"
EXTERNAL_NAME="$(safe_jsonpath service "$SERVICE_NAME" '{.spec.externalName}')"

SELECTOR="$(
    kubectl get service "$SERVICE_NAME" \
        --namespace "$NAMESPACE" \
        -o go-template='{{range $key, $value := .spec.selector}}{{printf "%s=%s," $key $value}}{{end}}' \
        2>/dev/null
)"
SELECTOR="${SELECTOR%,}"

mapfile -t MATCHING_PODS < <(
    if [[ -n "$SELECTOR" ]]; then
        kubectl get pods \
            --namespace "$NAMESPACE" \
            --selector "$SELECTOR" \
            -o name 2>/dev/null |
        sed 's#^pod/##'
    fi
)

mapfile -t ENDPOINT_SLICES < <(
    kubectl get endpointslices \
        --namespace "$NAMESPACE" \
        --selector "kubernetes.io/service-name=${SERVICE_NAME}" \
        -o name 2>/dev/null |
    sed 's#^endpointslice.discovery.k8s.io/##'
)

section "Kubernetes Service Dependency Check"

echo "Generated at:       $(date)"
echo "Kubernetes context: $CONTEXT"
echo "Namespace:          $NAMESPACE"
echo "Service:            $SERVICE_NAME"
echo "Service type:       ${SERVICE_TYPE:-unknown}"
echo "Cluster IP:         ${CLUSTER_IP:-<none>}"
echo "ExternalName:       ${EXTERNAL_NAME:-<none>}"
echo "Pod selector:       ${SELECTOR:-<none>}"
echo "Output file:        $OUTPUT_FILE"

section "1. RBAC Access Check"

for resource in services pods endpoints endpointslices events networkpolicies; do
    printf "%-34s " "get/list $resource:"

    if kubectl auth can-i list "$resource" \
        --namespace "$NAMESPACE" >/dev/null 2>&1
    then
        kubectl auth can-i list "$resource" \
            --namespace "$NAMESPACE" 2>/dev/null || echo "unknown"
    else
        kubectl auth can-i get "$resource" \
            --namespace "$NAMESPACE" 2>/dev/null || echo "unknown"
    fi
done

section "2. Service Overview"

run_command kubectl get service "$SERVICE_NAME" \
    --namespace "$NAMESPACE" \
    -o wide

run_command kubectl get service "$SERVICE_NAME" \
    --namespace "$NAMESPACE" \
    -o custom-columns='NAME:.metadata.name,TYPE:.spec.type,CLUSTER_IP:.spec.clusterIP,EXTERNAL_NAME:.spec.externalName,SESSION_AFFINITY:.spec.sessionAffinity,INTERNAL_TRAFFIC_POLICY:.spec.internalTrafficPolicy,EXTERNAL_TRAFFIC_POLICY:.spec.externalTrafficPolicy,IP_FAMILIES:.spec.ipFamilies[*]'

section "3. Service Ports"

kubectl get service "$SERVICE_NAME" \
    --namespace "$NAMESPACE" \
    -o go-template='
{{range .spec.ports}}
Name: {{if .name}}{{.name}}{{else}}<unnamed>{{end}}
Protocol: {{.protocol}}
Service port: {{.port}}
Target port: {{.targetPort}}
Node port: {{if .nodePort}}{{.nodePort}}{{else}}<none>{{end}}
App protocol: {{if .appProtocol}}{{.appProtocol}}{{else}}<none>{{end}}
---
{{end}}' 2>&1 || echo "[WARN] Could not retrieve Service ports."

section "4. Service Description"

run_command kubectl describe service "$SERVICE_NAME" \
    --namespace "$NAMESPACE"

section "5. Selector Analysis"

if [[ "$SERVICE_TYPE" == "ExternalName" ]]; then
    echo "This is an ExternalName Service."
    echo "It does not select Pods or create normal EndpointSlices."
    echo "External DNS target: ${EXTERNAL_NAME:-<not configured>}"
elif [[ -z "$SELECTOR" ]]; then
    echo "The Service has no selector."
    echo
    echo "Possible explanations:"
    echo "- the endpoints are managed manually"
    echo "- the Service is backed by an external system"
    echo "- EndpointSlices are created by another controller"
    echo "- the Service is intentionally selectorless"
else
    echo "Selector: $SELECTOR"
    echo
    echo "Matching Pod count: ${#MATCHING_PODS[@]}"
fi

section "6. Matching Pods"

if [[ -z "$SELECTOR" ]]; then
    echo "Matching Pods cannot be derived because the Service has no selector."
elif [[ "${#MATCHING_PODS[@]}" -eq 0 ]]; then
    echo "[WARN] No Pods match the Service selector:"
    echo "  $SELECTOR"
else
    run_command kubectl get pods \
        "${MATCHING_PODS[@]}" \
        --namespace "$NAMESPACE" \
        -o wide

    run_command kubectl get pods \
        "${MATCHING_PODS[@]}" \
        --namespace "$NAMESPACE" \
        -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[*].ready,POD_READY:.status.conditions[?(@.type=="Ready")].status,RESTARTS:.status.containerStatuses[*].restartCount,POD_IP:.status.podIP,NODE:.spec.nodeName,LABELS:.metadata.labels'
fi

section "7. Declared Container Ports"

if [[ "${#MATCHING_PODS[@]}" -eq 0 ]]; then
    echo "No matching Pods are available for container-port inspection."
else
    for pod_name in "${MATCHING_PODS[@]}"; do
        subsection "Pod: $pod_name"

        kubectl get pod "$pod_name" \
            --namespace "$NAMESPACE" \
            -o go-template='
{{range .spec.initContainers}}
Init container: {{.name}}
{{range .ports}}  Port name={{if .name}}{{.name}}{{else}}<unnamed>{{end}} containerPort={{.containerPort}} protocol={{.protocol}}
{{end}}{{end}}
{{range .spec.containers}}
Application container: {{.name}}
{{if .ports}}{{range .ports}}  Port name={{if .name}}{{.name}}{{else}}<unnamed>{{end}} containerPort={{.containerPort}} protocol={{.protocol}}
{{end}}{{else}}  No container ports declared.
{{end}}{{end}}' 2>&1 || echo "[WARN] Could not retrieve declared ports for Pod '$pod_name'."
    done
fi

section "8. EndpointSlices"

if [[ "${#ENDPOINT_SLICES[@]}" -eq 0 ]]; then
    echo "[WARN] No EndpointSlices were found for Service '$SERVICE_NAME'."
else
    run_command kubectl get endpointslices \
        "${ENDPOINT_SLICES[@]}" \
        --namespace "$NAMESPACE" \
        -o wide

    for slice_name in "${ENDPOINT_SLICES[@]}"; do
        subsection "EndpointSlice: $slice_name"

        kubectl get endpointslice "$slice_name" \
            --namespace "$NAMESPACE" \
            -o go-template='
Address type: {{.addressType}}
Ports:
{{range .ports}}  name={{if .name}}{{.name}}{{else}}<unnamed>{{end}} port={{if .port}}{{.port}}{{else}}<none>{{end}} protocol={{.protocol}} appProtocol={{if .appProtocol}}{{.appProtocol}}{{else}}<none>{{end}}
{{end}}
Endpoints:
{{range .endpoints}}  addresses={{.addresses}} ready={{if eq .conditions.ready nil}}<unknown>{{else}}{{.conditions.ready}}{{end}} serving={{if eq .conditions.serving nil}}<unknown>{{else}}{{.conditions.serving}}{{end}} terminating={{if eq .conditions.terminating nil}}false{{else}}{{.conditions.terminating}}{{end}} targetRef={{if .targetRef}}{{.targetRef.kind}}/{{.targetRef.name}}{{else}}<none>{{end}} node={{if .nodeName}}{{.nodeName}}{{else}}<none>{{end}}
{{end}}' 2>&1 || echo "[WARN] Could not retrieve EndpointSlice '$slice_name'."
    done
fi

section "9. Legacy Endpoints Object"

if kubectl get endpoints "$SERVICE_NAME" \
    --namespace "$NAMESPACE" >/dev/null 2>&1
then
    run_command kubectl get endpoints "$SERVICE_NAME" \
        --namespace "$NAMESPACE" \
        -o wide

    run_command kubectl describe endpoints "$SERVICE_NAME" \
        --namespace "$NAMESPACE"
else
    echo "No legacy Endpoints object is available."
fi

section "10. Pod-to-Endpoint Consistency"

declare -A POD_IP_TO_NAME=()
declare -A ENDPOINT_IP_SET=()

for pod_name in "${MATCHING_PODS[@]}"; do
    pod_ip="$(
        kubectl get pod "$pod_name" \
            --namespace "$NAMESPACE" \
            -o jsonpath='{.status.podIP}' 2>/dev/null
    )"

    if [[ -n "$pod_ip" ]]; then
        POD_IP_TO_NAME["$pod_ip"]="$pod_name"
    fi
done

while IFS= read -r endpoint_ip; do
    [[ -n "$endpoint_ip" ]] && ENDPOINT_IP_SET["$endpoint_ip"]=1
done < <(
    kubectl get endpointslices \
        --namespace "$NAMESPACE" \
        --selector "kubernetes.io/service-name=${SERVICE_NAME}" \
        -o go-template='{{range .items}}{{range .endpoints}}{{range .addresses}}{{printf "%s\n" .}}{{end}}{{end}}{{end}}' \
        2>/dev/null |
    sed '/^$/d' |
    sort -u
)

if [[ -z "$SELECTOR" ]]; then
    echo "Pod-to-endpoint comparison was skipped because the Service has no selector."
elif [[ "${#MATCHING_PODS[@]}" -eq 0 ]]; then
    echo "Pod-to-endpoint comparison was skipped because no Pods match the selector."
else
    echo "Selected Pod IPs:"
    for pod_ip in "${!POD_IP_TO_NAME[@]}"; do
        endpoint_status="missing from EndpointSlices"

        if [[ -n "${ENDPOINT_IP_SET[$pod_ip]:-}" ]]; then
            endpoint_status="present in EndpointSlices"
        fi

        echo "  ${POD_IP_TO_NAME[$pod_ip]} -> $pod_ip -> $endpoint_status"
    done

    echo
    echo "Endpoint addresses not mapped to selected Pod IPs:"

    UNMAPPED_ENDPOINTS=0

    for endpoint_ip in "${!ENDPOINT_IP_SET[@]}"; do
        if [[ -z "${POD_IP_TO_NAME[$endpoint_ip]:-}" ]]; then
            echo "  $endpoint_ip"
            UNMAPPED_ENDPOINTS=$((UNMAPPED_ENDPOINTS + 1))
        fi
    done

    if [[ "$UNMAPPED_ENDPOINTS" -eq 0 ]]; then
        echo "  None"
    fi
fi

section "11. Service and Endpoint Events"

subsection "Service Events"

kubectl get events \
    --namespace "$NAMESPACE" \
    --field-selector "involvedObject.kind=Service,involvedObject.name=${SERVICE_NAME}" \
    --sort-by='.metadata.creationTimestamp' \
    2>&1 || echo "[WARN] Could not retrieve Service events."

subsection "EndpointSlice Events"

if [[ "${#ENDPOINT_SLICES[@]}" -eq 0 ]]; then
    echo "No EndpointSlices are available for event inspection."
else
    for slice_name in "${ENDPOINT_SLICES[@]}"; do
        echo
        echo "--- EndpointSlice: $slice_name ---"

        kubectl get events \
            --namespace "$NAMESPACE" \
            --field-selector "involvedObject.kind=EndpointSlice,involvedObject.name=${slice_name}" \
            --sort-by='.metadata.creationTimestamp' \
            2>&1 || echo "[WARN] Could not retrieve events for EndpointSlice '$slice_name'."
    done
fi

section "12. Network Policies"

if kubectl auth can-i list networkpolicies \
    --namespace "$NAMESPACE" 2>/dev/null | grep -qx "yes"
then
    run_command kubectl get networkpolicies \
        --namespace "$NAMESPACE" \
        -o wide

    if kubectl get networkpolicies \
        --namespace "$NAMESPACE" \
        --no-headers 2>/dev/null | grep -q .
    then
        echo
        echo "[INFO] NetworkPolicy presence does not automatically mean that traffic is blocked."
        echo "Review podSelector, policyTypes, ingress peers, and allowed ports."
    else
        echo "No NetworkPolicies are defined in the namespace."
    fi
else
    echo "NetworkPolicy inspection was skipped because access is not available."
fi

section "13. Diagnostic Summary"

MATCHING_POD_COUNT="${#MATCHING_PODS[@]}"
RUNNING_POD_COUNT=0
READY_POD_COUNT=0
PODS_WITH_RESTARTS=0
ENDPOINT_ADDRESS_COUNT="${#ENDPOINT_IP_SET[@]}"
READY_ENDPOINT_COUNT=0
NOT_READY_ENDPOINT_COUNT=0
TERMINATING_ENDPOINT_COUNT=0
SELECTED_PODS_MISSING_FROM_ENDPOINTS=0

for pod_name in "${MATCHING_PODS[@]}"; do
    phase="$(
        kubectl get pod "$pod_name" \
            --namespace "$NAMESPACE" \
            -o jsonpath='{.status.phase}' 2>/dev/null
    )"

    pod_ready="$(
        kubectl get pod "$pod_name" \
            --namespace "$NAMESPACE" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null
    )"

    restarts="$(
        kubectl get pod "$pod_name" \
            --namespace "$NAMESPACE" \
            -o jsonpath='{.status.containerStatuses[*].restartCount}' 2>/dev/null |
        tr ' ' '\n' |
        awk '/^[0-9]+$/ {total += $1} END {print total+0}'
    )"

    pod_ip="$(
        kubectl get pod "$pod_name" \
            --namespace "$NAMESPACE" \
            -o jsonpath='{.status.podIP}' 2>/dev/null
    )"

    [[ "$phase" == "Running" ]] && RUNNING_POD_COUNT=$((RUNNING_POD_COUNT + 1))
    [[ "$pod_ready" == "True" ]] && READY_POD_COUNT=$((READY_POD_COUNT + 1))

    if [[ "${restarts:-0}" -gt 0 ]]; then
        PODS_WITH_RESTARTS=$((PODS_WITH_RESTARTS + 1))
    fi

    if [[ -n "$pod_ip" && -z "${ENDPOINT_IP_SET[$pod_ip]:-}" ]]; then
        SELECTED_PODS_MISSING_FROM_ENDPOINTS=$((SELECTED_PODS_MISSING_FROM_ENDPOINTS + 1))
    fi
done

while IFS='|' read -r ready terminating; do
    [[ -z "$ready" && -z "$terminating" ]] && continue

    if [[ "$ready" == "true" || -z "$ready" || "$ready" == "<nil>" ]]; then
        READY_ENDPOINT_COUNT=$((READY_ENDPOINT_COUNT + 1))
    else
        NOT_READY_ENDPOINT_COUNT=$((NOT_READY_ENDPOINT_COUNT + 1))
    fi

    if [[ "$terminating" == "true" ]]; then
        TERMINATING_ENDPOINT_COUNT=$((TERMINATING_ENDPOINT_COUNT + 1))
    fi
done < <(
    kubectl get endpointslices \
        --namespace "$NAMESPACE" \
        --selector "kubernetes.io/service-name=${SERVICE_NAME}" \
        -o go-template='{{range .items}}{{range .endpoints}}{{printf "%v|%v\n" .conditions.ready .conditions.terminating}}{{end}}{{end}}' \
        2>/dev/null
)

echo "Service type:                         ${SERVICE_TYPE:-unknown}"
echo "Service selector:                     ${SELECTOR:-<none>}"
echo "Matching Pods:                        $MATCHING_POD_COUNT"
echo "Running matching Pods:                $RUNNING_POD_COUNT"
echo "Ready matching Pods:                  $READY_POD_COUNT"
echo "Matching Pods with restarts:          $PODS_WITH_RESTARTS"
echo "EndpointSlice objects:                ${#ENDPOINT_SLICES[@]}"
echo "Unique endpoint addresses:            $ENDPOINT_ADDRESS_COUNT"
echo "Ready or unknown-ready endpoints:     $READY_ENDPOINT_COUNT"
echo "Explicitly not-ready endpoints:       $NOT_READY_ENDPOINT_COUNT"
echo "Terminating endpoints:                $TERMINATING_ENDPOINT_COUNT"
echo "Selected Pods missing from endpoints: $SELECTED_PODS_MISSING_FROM_ENDPOINTS"

echo
echo "Interpretation:"

if [[ "$SERVICE_TYPE" == "ExternalName" ]]; then
    echo "- ExternalName Service: validate the external DNS name and upstream system separately."
elif [[ -z "$SELECTOR" ]]; then
    if [[ "$ENDPOINT_ADDRESS_COUNT" -gt 0 ]]; then
        echo "- Selectorless Service with manually or externally managed endpoints."
    else
        echo "- Selectorless Service with no discovered endpoint addresses."
    fi
elif [[ "$MATCHING_POD_COUNT" -eq 0 ]]; then
    echo "- No Pods match the Service selector."
elif [[ "$READY_POD_COUNT" -eq 0 ]]; then
    echo "- Matching Pods exist, but none are currently Ready."
elif [[ "$ENDPOINT_ADDRESS_COUNT" -eq 0 ]]; then
    echo "- Ready matching Pods exist, but the Service has no endpoint addresses."
elif [[ "$SELECTED_PODS_MISSING_FROM_ENDPOINTS" -gt 0 ]]; then
    echo "- One or more selected Pods are absent from EndpointSlices."
else
    echo "- Service selector, ready Pods, and EndpointSlice addresses are consistent."
fi

if [[ "$PODS_WITH_RESTARTS" -gt 0 ]]; then
    echo "- One or more backend Pods have container restart history."
fi

echo
echo "Service dependency check completed."
echo "Output saved to:"
echo "  $OUTPUT_FILE"

if [[ "${#MATCHING_PODS[@]}" -gt 0 ]]; then
    echo
    echo "Recommended Pod-level diagnostics:"

    for pod_name in "${MATCHING_PODS[@]}"; do
        echo "  ./scripts/03_pod_diagnostics.sh $NAMESPACE $pod_name"
    done
fi

section "End of Kubernetes Service Dependency Check"