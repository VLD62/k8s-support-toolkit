#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NAMESPACE=""
WORKLOAD_KIND=""
WORKLOAD_NAME=""
OUTPUT_ROOT="outputs"
LOG_TAIL="200"
CREATE_ARCHIVE=false

declare -a POD_NAMES=()
declare -a SERVICE_NAMES=()
declare -a STEP_NAMES=()
declare -a STEP_RESULTS=()
declare -a AUTO_DISCOVERED_PODS=()

usage() {
    cat <<'EOF'
Usage:
  05_collect_troubleshooting_bundle.sh \
    --namespace <namespace> \
    [--workload <kind> <name>] \
    [--pod <pod-name>]... \
    [--service <service-name>]... \
    [--output-dir <directory>] \
    [--log-tail <lines>] \
    [--archive]

Required:
  --namespace <namespace>
      Kubernetes namespace to inspect.

Optional:
  --workload <kind> <name>
      Run controller-level diagnostics.
      Supported kinds are handled by 02_workload_diagnostics.sh.

  --pod <pod-name>
      Run Pod diagnostics. May be supplied multiple times.

  --service <service-name>
      Run Service dependency checks. May be supplied multiple times.

  --output-dir <directory>
      Root directory for generated bundles.
      Default: outputs

  --log-tail <lines>
      Number of current and previous log lines collected per container.
      Default: 200

  --archive
      Create a .tar.gz archive next to the bundle directory.

Examples:
  ./scripts/05_collect_troubleshooting_bundle.sh \
    --namespace example-app

  ./scripts/05_collect_troubleshooting_bundle.sh \
    --namespace example-app \
    --workload deployment example-api \
    --service example-api \
    --archive

  ./scripts/05_collect_troubleshooting_bundle.sh \
    --namespace example-app \
    --workload statefulset example-worker \
    --pod example-worker-0 \
    --service example-worker \
    --log-tail 300 \
    --archive
EOF
}

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

sanitize() {
    printf '%s' "$1" | tr '/ :@' '_____'
}

normalize_kind() {
    case "${1,,}" in
        deployment|deploy|deployments)
            echo "deployment"
            ;;
        statefulset|statefulsets|sts)
            echo "statefulset"
            ;;
        daemonset|daemonsets|ds)
            echo "daemonset"
            ;;
        job|jobs)
            echo "job"
            ;;
        cronjob|cronjobs|cj)
            echo "cronjob"
            ;;
        *)
            echo "$1"
            ;;
    esac
}

append_unique() {
    local value="$1"
    local array_name="$2"
    local existing=""

    eval "for existing in \"\${${array_name}[@]}\"; do
        [[ \"\$existing\" == \"\$value\" ]] && return 0
    done"

    eval "${array_name}+=(\"\$value\")"
}

record_step() {
    STEP_NAMES+=("$1")
    STEP_RESULTS+=("$2")
}

run_step() {
    local step_name="$1"
    shift

    section "$step_name"

    echo "\$ $*"
    echo

    "$@"
    local rc=$?

    if [[ "$rc" -eq 0 ]]; then
        echo
        echo "[OK] $step_name completed successfully."
        record_step "$step_name" "SUCCESS"
    else
        echo
        echo "[WARN] $step_name finished with exit code $rc."
        record_step "$step_name" "FAILED ($rc)"
    fi

    return 0
}

discover_workload_pods() {
    local kind="$1"
    local name="$2"
    local selector=""

    case "$kind" in
        deployment|statefulset|daemonset)
            selector="$(
                kubectl get "$kind" "$name" \
                    --namespace "$NAMESPACE" \
                    -o go-template='{{range $key, $value := .spec.selector.matchLabels}}{{printf "%s=%s," $key $value}}{{end}}' \
                    2>/dev/null
            )"
            selector="${selector%,}"

            if [[ -n "$selector" ]]; then
                mapfile -t AUTO_DISCOVERED_PODS < <(
                    kubectl get pods \
                        --namespace "$NAMESPACE" \
                        --selector "$selector" \
                        -o name 2>/dev/null |
                    sed 's#^pod/##' |
                    sort
                )
            fi
            ;;

        job)
            mapfile -t AUTO_DISCOVERED_PODS < <(
                kubectl get pods \
                    --namespace "$NAMESPACE" \
                    --selector "job-name=$name" \
                    -o name 2>/dev/null |
                sed 's#^pod/##' |
                sort
            )
            ;;

        cronjob)
            echo "[INFO] Automatic Pod discovery is skipped for CronJobs."
            echo "       Supply one or more --pod arguments for the relevant Job Pods."
            ;;
    esac
}

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --namespace|-n)
            [[ "$#" -ge 2 ]] || {
                echo "[ERROR] --namespace requires a value."
                exit 1
            }
            NAMESPACE="$2"
            shift 2
            ;;

        --workload|-w)
            [[ "$#" -ge 3 ]] || {
                echo "[ERROR] --workload requires <kind> <name>."
                exit 1
            }
            WORKLOAD_KIND="$(normalize_kind "$2")"
            WORKLOAD_NAME="$3"
            shift 3
            ;;

        --pod|-p)
            [[ "$#" -ge 2 ]] || {
                echo "[ERROR] --pod requires a value."
                exit 1
            }
            append_unique "$2" POD_NAMES
            shift 2
            ;;

        --service|-s)
            [[ "$#" -ge 2 ]] || {
                echo "[ERROR] --service requires a value."
                exit 1
            }
            append_unique "$2" SERVICE_NAMES
            shift 2
            ;;

        --output-dir|-o)
            [[ "$#" -ge 2 ]] || {
                echo "[ERROR] --output-dir requires a value."
                exit 1
            }
            OUTPUT_ROOT="$2"
            shift 2
            ;;

        --log-tail)
            [[ "$#" -ge 2 ]] || {
                echo "[ERROR] --log-tail requires a value."
                exit 1
            }
            LOG_TAIL="$2"
            shift 2
            ;;

        --archive)
            CREATE_ARCHIVE=true
            shift
            ;;

        --help|-h)
            usage
            exit 0
            ;;

        *)
            echo "[ERROR] Unknown argument: $1"
            echo
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$NAMESPACE" ]]; then
    echo "[ERROR] --namespace is required."
    echo
    usage
    exit 1
fi

if ! [[ "$LOG_TAIL" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] --log-tail must be a non-negative integer."
    exit 1
fi

if [[ -n "$WORKLOAD_KIND" && -z "$WORKLOAD_NAME" ]] ||
   [[ -z "$WORKLOAD_KIND" && -n "$WORKLOAD_NAME" ]]
then
    echo "[ERROR] Workload kind and workload name must be supplied together."
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

SCRIPT_01="${SCRIPT_DIR}/01_namespace_workload_overview.sh"
SCRIPT_02="${SCRIPT_DIR}/02_workload_diagnostics.sh"
SCRIPT_03="${SCRIPT_DIR}/03_pod_diagnostics.sh"
SCRIPT_04="${SCRIPT_DIR}/04_service_dependency_check.sh"

if [[ ! -f "$SCRIPT_01" ]]; then
    echo "[ERROR] Required script was not found:"
    echo "  $SCRIPT_01"
    exit 1
fi

if [[ -n "$WORKLOAD_NAME" && ! -f "$SCRIPT_02" ]]; then
    echo "[ERROR] Workload diagnostics script was not found:"
    echo "  $SCRIPT_02"
    exit 1
fi

if [[ "${#POD_NAMES[@]}" -gt 0 && ! -f "$SCRIPT_03" ]]; then
    echo "[ERROR] Pod diagnostics script was not found:"
    echo "  $SCRIPT_03"
    exit 1
fi

if [[ "${#SERVICE_NAMES[@]}" -gt 0 && ! -f "$SCRIPT_04" ]]; then
    echo "[ERROR] Service dependency script was not found:"
    echo "  $SCRIPT_04"
    exit 1
fi

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
SAFE_NAMESPACE="$(sanitize "$NAMESPACE")"
BUNDLE_NAME="troubleshooting_bundle_${SAFE_NAMESPACE}_${TIMESTAMP}"
BUNDLE_DIR="${OUTPUT_ROOT}/${BUNDLE_NAME}"
EXECUTION_LOG="${BUNDLE_DIR}/00_bundle_execution.log"
CONTEXT_FILE="${BUNDLE_DIR}/00_bundle_context.txt"
STATUS_FILE="${BUNDLE_DIR}/00_bundle_status.md"
CHECKSUM_FILE="${BUNDLE_DIR}/checksums.sha256"

mkdir -p "$BUNDLE_DIR"

exec > >(tee "$EXECUTION_LOG") 2>&1

CONTEXT="$(kubectl config current-context 2>/dev/null || echo "unknown")"

section "Kubernetes Troubleshooting Bundle"

echo "Generated at:       $(date)"
echo "Kubernetes context: $CONTEXT"
echo "Namespace:          $NAMESPACE"
echo "Bundle directory:   $BUNDLE_DIR"
echo "Log tail:           $LOG_TAIL lines"
echo "Create archive:     $CREATE_ARCHIVE"

if [[ -n "$WORKLOAD_NAME" ]]; then
    echo "Workload:           ${WORKLOAD_KIND}/${WORKLOAD_NAME}"
else
    echo "Workload:           <not supplied>"
fi

if [[ "${#POD_NAMES[@]}" -gt 0 ]]; then
    echo "Explicit Pods:      ${POD_NAMES[*]}"
else
    echo "Explicit Pods:      <none>"
fi

if [[ "${#SERVICE_NAMES[@]}" -gt 0 ]]; then
    echo "Services:           ${SERVICE_NAMES[*]}"
else
    echo "Services:           <none>"
fi

cat > "$CONTEXT_FILE" <<EOF
Kubernetes Troubleshooting Bundle Context
=========================================

Generated at:       $(date)
Kubernetes context: $CONTEXT
Namespace:          $NAMESPACE
Workload kind:      ${WORKLOAD_KIND:-<not supplied>}
Workload name:      ${WORKLOAD_NAME:-<not supplied>}
Explicit Pods:      ${POD_NAMES[*]:-<none>}
Services:           ${SERVICE_NAMES[*]:-<none>}
Log tail:           $LOG_TAIL
Bundle directory:   $BUNDLE_DIR

kubectl client and server version
---------------------------------
EOF

kubectl version >> "$CONTEXT_FILE" 2>&1 || true

cat >> "$CONTEXT_FILE" <<EOF

Current namespace
-----------------
EOF

kubectl get namespace "$NAMESPACE" -o wide >> "$CONTEXT_FILE" 2>&1 || true

if [[ -n "$WORKLOAD_NAME" && "${#POD_NAMES[@]}" -eq 0 ]]; then
    section "Automatic Pod Discovery"

    discover_workload_pods "$WORKLOAD_KIND" "$WORKLOAD_NAME"

    if [[ "${#AUTO_DISCOVERED_PODS[@]}" -eq 1 ]]; then
        echo "Exactly one Pod was discovered for the workload:"
        echo "  ${AUTO_DISCOVERED_PODS[0]}"
        append_unique "${AUTO_DISCOVERED_PODS[0]}" POD_NAMES
    elif [[ "${#AUTO_DISCOVERED_PODS[@]}" -gt 1 ]]; then
        echo "Multiple Pods were discovered for the workload:"
        printf '  %s\n' "${AUTO_DISCOVERED_PODS[@]}"
        echo
        echo "[INFO] Automatic Pod diagnostics were skipped to avoid collecting"
        echo "       unexpectedly large log bundles."
        echo "       Re-run with one or more explicit --pod arguments."
    else
        echo "No Pod could be discovered automatically for the workload."
    fi
fi

run_step \
    "01. Namespace Workload Overview" \
    bash "$SCRIPT_01" "$NAMESPACE" "$BUNDLE_DIR"

if [[ -n "$WORKLOAD_NAME" ]]; then
    run_step \
        "02. Workload Diagnostics — ${WORKLOAD_KIND}/${WORKLOAD_NAME}" \
        bash "$SCRIPT_02" \
            "$NAMESPACE" \
            "$WORKLOAD_KIND" \
            "$WORKLOAD_NAME" \
            "$BUNDLE_DIR"
else
    record_step "02. Workload Diagnostics" "SKIPPED — no workload supplied"
fi

if [[ "${#POD_NAMES[@]}" -gt 0 ]]; then
    for pod_name in "${POD_NAMES[@]}"; do
        if kubectl get pod "$pod_name" \
            --namespace "$NAMESPACE" >/dev/null 2>&1
        then
            run_step \
                "03. Pod Diagnostics — ${pod_name}" \
                bash "$SCRIPT_03" \
                    "$NAMESPACE" \
                    "$pod_name" \
                    "$BUNDLE_DIR" \
                    "$LOG_TAIL"
        else
            section "03. Pod Diagnostics — ${pod_name}"
            echo "[WARN] Pod '$pod_name' was not found or is not accessible."
            record_step "03. Pod Diagnostics — ${pod_name}" "FAILED — Pod not found"
        fi
    done
else
    record_step "03. Pod Diagnostics" "SKIPPED — no Pod supplied or uniquely discovered"
fi

if [[ "${#SERVICE_NAMES[@]}" -gt 0 ]]; then
    for service_name in "${SERVICE_NAMES[@]}"; do
        if kubectl get service "$service_name" \
            --namespace "$NAMESPACE" >/dev/null 2>&1
        then
            run_step \
                "04. Service Dependency Check — ${service_name}" \
                bash "$SCRIPT_04" \
                    "$NAMESPACE" \
                    "$service_name" \
                    "$BUNDLE_DIR"
        else
            section "04. Service Dependency Check — ${service_name}"
            echo "[WARN] Service '$service_name' was not found or is not accessible."
            record_step "04. Service Dependency Check — ${service_name}" "FAILED — Service not found"
        fi
    done
else
    record_step "04. Service Dependency Check" "SKIPPED — no Service supplied"
fi

section "Bundle Manifest"

{
    echo "# Kubernetes Troubleshooting Bundle"
    echo
    echo "| Field | Value |"
    echo "|---|---|"
    echo "| Generated | $(date) |"
    echo "| Kubernetes context | \`$CONTEXT\` |"
    echo "| Namespace | \`$NAMESPACE\` |"
    echo "| Workload | \`${WORKLOAD_KIND:-<none>}/${WORKLOAD_NAME:-<none>}\` |"
    echo "| Pods | \`${POD_NAMES[*]:-<none>}\` |"
    echo "| Services | \`${SERVICE_NAMES[*]:-<none>}\` |"
    echo "| Log tail | $LOG_TAIL lines |"
    echo
    echo "## Execution Status"
    echo
    echo "| Step | Result |"
    echo "|---|---|"

    for index in "${!STEP_NAMES[@]}"; do
        echo "| ${STEP_NAMES[$index]} | ${STEP_RESULTS[$index]} |"
    done

    echo
    echo "## Generated Files"
    echo

    find "$BUNDLE_DIR" \
        -maxdepth 1 \
        -type f \
        -printf '%f\n' 2>/dev/null |
    sort |
    while IFS= read -r filename; do
        echo "- \`$filename\`"
    done

    echo
    echo "## Handling Notice"
    echo
    echo "The bundle may contain internal resource names, image names, IP addresses,"
    echo "node names, configuration references, and application logs."
    echo
    echo "Secret values are not intentionally decoded by the scripts. However,"
    echo "\`kubectl describe\` and application logs may contain literal non-secret"
    echo "environment values or other operationally sensitive information."
    echo
    echo "Review the bundle before sharing it outside the intended support channel."
} > "$STATUS_FILE"

echo "Bundle status file:"
echo "  $STATUS_FILE"

section "Bundle Checksums"

: > "$CHECKSUM_FILE"

(
    cd "$BUNDLE_DIR" || exit 1

    while IFS= read -r -d '' file_path; do
        relative_path="${file_path#./}"
        sha256sum "$relative_path"
    done < <(
        find . \
            -maxdepth 1 \
            -type f \
            ! -name "$(basename "$CHECKSUM_FILE")" \
            ! -name "$(basename "$EXECUTION_LOG")" \
            -print0 2>/dev/null |
        sort -z
    )
) > "$CHECKSUM_FILE"

cat "$CHECKSUM_FILE"

ARCHIVE_PATH=""

section "Troubleshooting Bundle Summary"

SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

for result in "${STEP_RESULTS[@]}"; do
    case "$result" in
        SUCCESS)
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            ;;
        SKIPPED*)
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            ;;
        *)
            FAILED_COUNT=$((FAILED_COUNT + 1))
            ;;
    esac
done

echo "Successful steps: $SUCCESS_COUNT"
echo "Failed steps:     $FAILED_COUNT"
echo "Skipped steps:    $SKIPPED_COUNT"
echo
echo "Bundle directory:"
echo "  $BUNDLE_DIR"

echo "Archive requested: $CREATE_ARCHIVE"

echo
echo "Review the generated reports and bundle status before escalation."

if [[ "$CREATE_ARCHIVE" == true ]]; then
    section "Bundle Archive"

    ARCHIVE_PATH="${OUTPUT_ROOT}/${BUNDLE_NAME}.tar.gz"

    # Flush the execution log before reading the bundle directory into the archive.
    sync "$EXECUTION_LOG" 2>/dev/null || sync 2>/dev/null || true

    if tar \
        --create \
        --gzip \
        --file "$ARCHIVE_PATH" \
        --directory "$OUTPUT_ROOT" \
        "$BUNDLE_NAME"
    then
        echo "Archive created:"
        echo "  $ARCHIVE_PATH"

        if command -v sha256sum >/dev/null 2>&1; then
            echo
            echo "Archive checksum:"
            sha256sum "$ARCHIVE_PATH"
        fi
    else
        echo "[WARN] Archive creation failed."
        ARCHIVE_PATH=""
    fi
fi

section "End of Kubernetes Troubleshooting Bundle"