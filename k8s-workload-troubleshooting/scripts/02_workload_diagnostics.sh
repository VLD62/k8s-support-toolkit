#!/usr/bin/env bash

set -uo pipefail

NAMESPACE="${1:-}"
KIND_INPUT="${2:-}"
WORKLOAD_NAME="${3:-}"
OUTPUT_DIR="${4:-outputs}"

usage() {
    echo "Usage:"
    echo "  $0 <namespace> <workload-kind> <workload-name> [output-directory]"
    echo
    echo "Supported workload kinds:"
    echo "  deployment | statefulset | daemonset | job | cronjob"
    echo
    echo "Examples:"
    echo "  $0 example-app deployment example-api"
    echo "  $0 example-app statefulset example-worker"
    echo "  $0 example-gitops deployment example-gitops-server"
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
        echo "[WARN] Command failed, timed out, or access was denied."
    fi
}

normalize_kind() {
    case "${KIND_INPUT,,}" in
        deployment|deploy|deployments)
            RESOURCE="deployment"
            OBJECT_KIND="Deployment"
            ;;
        statefulset|statefulsets|sts)
            RESOURCE="statefulset"
            OBJECT_KIND="StatefulSet"
            ;;
        daemonset|daemonsets|ds)
            RESOURCE="daemonset"
            OBJECT_KIND="DaemonSet"
            ;;
        job|jobs)
            RESOURCE="job"
            OBJECT_KIND="Job"
            ;;
        cronjob|cronjobs|cj)
            RESOURCE="cronjob"
            OBJECT_KIND="CronJob"
            ;;
        *)
            echo "[ERROR] Unsupported workload kind: '$KIND_INPUT'"
            echo
            usage
            exit 1
            ;;
    esac
}

if [[ -z "$NAMESPACE" || -z "$KIND_INPUT" || -z "$WORKLOAD_NAME" ]]; then
    usage
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "[ERROR] kubectl was not found in PATH."
    exit 1
fi

normalize_kind

if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "[ERROR] Namespace '$NAMESPACE' does not exist or is not accessible."
    exit 1
fi

if ! kubectl get "$RESOURCE" "$WORKLOAD_NAME" \
    --namespace "$NAMESPACE" >/dev/null 2>&1
then
    echo "[ERROR] $OBJECT_KIND '$WORKLOAD_NAME' was not found in namespace '$NAMESPACE'."
    exit 1
fi

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"

SAFE_NAMESPACE="$(echo "$NAMESPACE" | tr '/ ' '__')"
SAFE_KIND="$(echo "$RESOURCE" | tr '/ ' '__')"
SAFE_NAME="$(echo "$WORKLOAD_NAME" | tr '/ ' '__')"

mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="${OUTPUT_DIR}/02_workload_diagnostics_${SAFE_NAMESPACE}_${SAFE_KIND}_${SAFE_NAME}_${TIMESTAMP}.txt"

exec > >(tee "$OUTPUT_FILE") 2>&1

CONTEXT="$(kubectl config current-context 2>/dev/null || echo "unknown")"

SELECTOR=""
declare -a PODS=()
declare -a RELATED_JOBS=()

section "Kubernetes Workload Diagnostics"

echo "Generated at:       $(date)"
echo "Kubernetes context: $CONTEXT"
echo "Namespace:          $NAMESPACE"
echo "Workload kind:      $OBJECT_KIND"
echo "Workload name:      $WORKLOAD_NAME"
echo "Output file:        $OUTPUT_FILE"

section "1. Workload Overview"

run_command kubectl get "$RESOURCE" "$WORKLOAD_NAME" \
    --namespace "$NAMESPACE" \
    -o wide

section "2. Workload Status"

case "$RESOURCE" in
    deployment)
        run_command kubectl get deployment "$WORKLOAD_NAME" \
            --namespace "$NAMESPACE" \
            -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,UPDATED:.status.updatedReplicas,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas,UNAVAILABLE:.status.unavailableReplicas,OBSERVED_GENERATION:.status.observedGeneration,GENERATION:.metadata.generation'
        ;;

    statefulset)
        run_command kubectl get statefulset "$WORKLOAD_NAME" \
            --namespace "$NAMESPACE" \
            -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,CURRENT:.status.currentReplicas,UPDATED:.status.updatedReplicas,READY:.status.readyReplicas,CURRENT_REVISION:.status.currentRevision,UPDATE_REVISION:.status.updateRevision,OBSERVED_GENERATION:.status.observedGeneration,GENERATION:.metadata.generation'
        ;;

    daemonset)
        run_command kubectl get daemonset "$WORKLOAD_NAME" \
            --namespace "$NAMESPACE" \
            -o custom-columns='NAME:.metadata.name,DESIRED:.status.desiredNumberScheduled,CURRENT:.status.currentNumberScheduled,READY:.status.numberReady,AVAILABLE:.status.numberAvailable,UNAVAILABLE:.status.numberUnavailable,MISSCHEDULED:.status.numberMisscheduled,UPDATED:.status.updatedNumberScheduled'
        ;;

    job)
        run_command kubectl get job "$WORKLOAD_NAME" \
            --namespace "$NAMESPACE" \
            -o custom-columns='NAME:.metadata.name,COMPLETIONS:.spec.completions,PARALLELISM:.spec.parallelism,ACTIVE:.status.active,SUCCEEDED:.status.succeeded,FAILED:.status.failed,START_TIME:.status.startTime,COMPLETION_TIME:.status.completionTime'
        ;;

    cronjob)
        run_command kubectl get cronjob "$WORKLOAD_NAME" \
            --namespace "$NAMESPACE" \
            -o custom-columns='NAME:.metadata.name,SCHEDULE:.spec.schedule,SUSPEND:.spec.suspend,ACTIVE:.status.active[*].name,LAST_SCHEDULE:.status.lastScheduleTime,LAST_SUCCESS:.status.lastSuccessfulTime'
        ;;
esac

section "3. Workload Conditions"

run_command kubectl get "$RESOURCE" "$WORKLOAD_NAME" \
    --namespace "$NAMESPACE" \
    -o custom-columns='TYPE:.status.conditions[*].type,STATUS:.status.conditions[*].status,REASON:.status.conditions[*].reason,MESSAGE:.status.conditions[*].message'

section "4. Workload Description"

run_command kubectl describe "$RESOURCE" "$WORKLOAD_NAME" \
    --namespace "$NAMESPACE"

section "5. Rollout Status"

case "$RESOURCE" in
    deployment|statefulset|daemonset)
        run_command kubectl rollout status \
            "$RESOURCE/$WORKLOAD_NAME" \
            --namespace "$NAMESPACE" \
            --timeout=10s
        ;;

    job)
        echo "Rollout status is not applicable to Jobs."
        echo "Review Job conditions, active Pods, succeeded count, and failed count."
        ;;

    cronjob)
        echo "Rollout status is not applicable to CronJobs."
        echo "Review the schedule, suspension state, related Jobs, and their Pods."
        ;;
esac

section "6. Workload Selector and Related Objects"

case "$RESOURCE" in
    deployment|statefulset|daemonset)
        SELECTOR="$(
            kubectl get "$RESOURCE" "$WORKLOAD_NAME" \
                --namespace "$NAMESPACE" \
                -o go-template='{{range $key, $value := .spec.selector.matchLabels}}{{printf "%s=%s," $key $value}}{{end}}' \
                2>/dev/null
        )"

        SELECTOR="${SELECTOR%,}"

        if [[ -n "$SELECTOR" ]]; then
            echo "Pod selector: $SELECTOR"
        else
            echo "[WARN] No matchLabels selector could be determined."
        fi
        ;;

    job)
        SELECTOR="job-name=$WORKLOAD_NAME"
        echo "Pod selector: $SELECTOR"
        ;;

    cronjob)
        echo "Related Jobs:"

        mapfile -t RELATED_JOBS < <(
            kubectl get jobs \
                --namespace "$NAMESPACE" \
                --no-headers \
                -o custom-columns='NAME:.metadata.name,OWNER_KIND:.metadata.ownerReferences[0].kind,OWNER_NAME:.metadata.ownerReferences[0].name' \
                2>/dev/null |
            awk -v cronjob="$WORKLOAD_NAME" \
                '$2 == "CronJob" && $3 == cronjob {print $1}'
        )

        if [[ "${#RELATED_JOBS[@]}" -eq 0 ]]; then
            echo "No Jobs owned by this CronJob were found."
        else
            printf '%s\n' "${RELATED_JOBS[@]}"
        fi
        ;;
esac

case "$RESOURCE" in
    deployment)
        if [[ -n "$SELECTOR" ]]; then
            run_command kubectl get replicasets \
                --namespace "$NAMESPACE" \
                --selector "$SELECTOR" \
                -o wide
        fi
        ;;

    statefulset|daemonset)
        if [[ -n "$SELECTOR" ]]; then
            run_command kubectl get controllerrevisions \
                --namespace "$NAMESPACE" \
                --selector "$SELECTOR"
        fi
        ;;

    job)
        run_command kubectl get job "$WORKLOAD_NAME" \
            --namespace "$NAMESPACE" \
            -o custom-columns='NAME:.metadata.name,OWNER_KIND:.metadata.ownerReferences[0].kind,OWNER_NAME:.metadata.ownerReferences[0].name'
        ;;

    cronjob)
        if [[ "${#RELATED_JOBS[@]}" -gt 0 ]]; then
            run_command kubectl get jobs \
                "${RELATED_JOBS[@]}" \
                --namespace "$NAMESPACE" \
                -o wide
        fi
        ;;
esac

section "7. Matching Pods"

case "$RESOURCE" in
    deployment|statefulset|daemonset|job)
        if [[ -n "$SELECTOR" ]]; then
            mapfile -t PODS < <(
                kubectl get pods \
                    --namespace "$NAMESPACE" \
                    --selector "$SELECTOR" \
                    -o name 2>/dev/null |
                sed 's#^pod/##'
            )
        fi
        ;;

    cronjob)
        for job_name in "${RELATED_JOBS[@]}"; do
            while IFS= read -r pod_name; do
                [[ -n "$pod_name" ]] && PODS+=("$pod_name")
            done < <(
                kubectl get pods \
                    --namespace "$NAMESPACE" \
                    --selector "job-name=$job_name" \
                    -o name 2>/dev/null |
                sed 's#^pod/##'
            )
        done
        ;;
esac

if [[ "${#PODS[@]}" -gt 0 ]]; then
    mapfile -t PODS < <(
        printf '%s\n' "${PODS[@]}" |
        sed '/^$/d' |
        sort -u
    )
fi

if [[ "${#PODS[@]}" -eq 0 ]]; then
    echo "No matching Pods were found."
else
    run_command kubectl get pods \
        "${PODS[@]}" \
        --namespace "$NAMESPACE" \
        -o wide
fi

section "8. Pod and Container Status"

if [[ "${#PODS[@]}" -eq 0 ]]; then
    echo "No matching Pods are available for container status inspection."
else
    run_command kubectl get pods \
        "${PODS[@]}" \
        --namespace "$NAMESPACE" \
        -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount,WAITING_REASON:.status.containerStatuses[*].state.waiting.reason,LAST_REASON:.status.containerStatuses[*].lastState.terminated.reason,INIT_RESTARTS:.status.initContainerStatuses[*].restartCount,INIT_LAST_REASON:.status.initContainerStatuses[*].lastState.terminated.reason,NODE:.spec.nodeName'
fi

section "9. Workload Events"

kubectl get events \
    --namespace "$NAMESPACE" \
    --field-selector "involvedObject.kind=${OBJECT_KIND},involvedObject.name=${WORKLOAD_NAME}" \
    --sort-by='.metadata.creationTimestamp' \
    2>&1 || echo "[WARN] Could not retrieve workload events."

section "10. Pod Events"

if [[ "${#PODS[@]}" -eq 0 ]]; then
    echo "No matching Pods are available for event inspection."
else
    for pod_name in "${PODS[@]}"; do
        echo
        echo "--- Pod: $pod_name ---"

        kubectl get events \
            --namespace "$NAMESPACE" \
            --field-selector "involvedObject.kind=Pod,involvedObject.name=${pod_name}" \
            --sort-by='.metadata.creationTimestamp' \
            2>&1 || echo "[WARN] Could not retrieve events for Pod '$pod_name'."
    done
fi

section "11. Pod Resource Usage"

if [[ "${#PODS[@]}" -eq 0 ]]; then
    echo "No matching Pods are available for resource usage inspection."
elif [[ -n "$SELECTOR" ]] &&
    kubectl top pods \
        --namespace "$NAMESPACE" \
        --selector "$SELECTOR" \
        >/dev/null 2>&1
then
    run_command kubectl top pods \
        --namespace "$NAMESPACE" \
        --selector "$SELECTOR" \
        --containers
else
    METRICS_AVAILABLE=false

    for pod_name in "${PODS[@]}"; do
        if kubectl top pod "$pod_name" \
            --namespace "$NAMESPACE" >/dev/null 2>&1
        then
            METRICS_AVAILABLE=true
            run_command kubectl top pod "$pod_name" \
                --namespace "$NAMESPACE" \
                --containers
        fi
    done

    if [[ "$METRICS_AVAILABLE" == false ]]; then
        echo "Pod metrics are unavailable."
        echo "Metrics Server may be unavailable or access may be denied."
    fi
fi

section "12. Diagnostic Summary"

TOTAL_PODS="${#PODS[@]}"
NOT_READY_PODS=0
PODS_WITH_RESTARTS=0
TOTAL_CONTAINER_RESTARTS=0

for pod_name in "${PODS[@]}"; do
    PHASE="$(
        kubectl get pod "$pod_name" \
            --namespace "$NAMESPACE" \
            -o jsonpath='{.status.phase}' 2>/dev/null
    )"

    READY_FLAGS="$(
        kubectl get pod "$pod_name" \
            --namespace "$NAMESPACE" \
            -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null
    )"

    APPLICATION_RESTARTS="$(
        kubectl get pod "$pod_name" \
            --namespace "$NAMESPACE" \
            -o jsonpath='{.status.containerStatuses[*].restartCount}' 2>/dev/null
    )"

    INIT_RESTARTS="$(
        kubectl get pod "$pod_name" \
            --namespace "$NAMESPACE" \
            -o jsonpath='{.status.initContainerStatuses[*].restartCount}' 2>/dev/null
    )"

    POD_RESTARTS="$(
        printf '%s %s\n' "$APPLICATION_RESTARTS" "$INIT_RESTARTS" |
        tr ' ' '\n' |
        awk '
            /^[0-9]+$/ {
                total += $1
            }
            END {
                print total+0
            }
        '
    )"

    if [[ "$PHASE" != "Succeeded" ]]; then
        if [[ -z "$READY_FLAGS" || "$READY_FLAGS" == *"false"* ]]; then
            NOT_READY_PODS=$((NOT_READY_PODS + 1))
        fi
    fi

    if [[ "$POD_RESTARTS" -gt 0 ]]; then
        PODS_WITH_RESTARTS=$((PODS_WITH_RESTARTS + 1))
    fi

    TOTAL_CONTAINER_RESTARTS=$((TOTAL_CONTAINER_RESTARTS + POD_RESTARTS))
done

echo "Matching Pods:                   $TOTAL_PODS"
echo "Not-ready Pods:                  $NOT_READY_PODS"
echo "Pods with container restarts:    $PODS_WITH_RESTARTS"
echo "Total container restart count:   $TOTAL_CONTAINER_RESTARTS"

echo
echo "Workload diagnostics completed."
echo "Output saved to:"
echo "  $OUTPUT_FILE"

if [[ "${#PODS[@]}" -gt 0 ]]; then
    echo
    echo "Recommended next-level Pod diagnostics:"

    for pod_name in "${PODS[@]}"; do
        echo "  ./scripts/03_pod_diagnostics.sh $NAMESPACE $pod_name"
    done
fi

section "End of Kubernetes Workload Diagnostics"