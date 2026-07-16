#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLSET_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
OUTPUT_DIR="${OUTPUT_DIR:-${TOOLSET_DIR}/output}"
OUTPUT_FILE="${OUTPUT_DIR}/03_argocd_sync_health_diagnostics_${TIMESTAMP}.txt"

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

mkdir -p "${OUTPUT_DIR}"

exec > >(tee "${OUTPUT_FILE}") 2>&1

print_header() {
    echo
    echo "======================================================================"
    echo "$1"
    echo "======================================================================"
}

print_subheader() {
    echo
    echo "----------------------------------------------------------------------"
    echo "$1"
    echo "----------------------------------------------------------------------"
}

get_application_field() {
    local application="$1"
    local jsonpath="$2"

    kubectl get applications.argoproj.io \
        "${application}" \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output "jsonpath=${jsonpath}" \
        2>/dev/null || true
}

sanitize_repository_url() {
    sed -E \
        -e 's#(https?://)[^/@]+@#\1***@#' \
        -e 's#(ssh://)[^/@]+@#\1***@#'
}

print_application_summary() {
    local application="$1"

    local repository
    local target_revision
    local source_path
    local destination_namespace
    local sync_status
    local health_status
    local revision
    local reconciled_at

    repository="$(
        get_application_field "${application}" '{.spec.source.repoURL}' |
            sanitize_repository_url
    )"

    target_revision="$(
        get_application_field "${application}" '{.spec.source.targetRevision}'
    )"

    source_path="$(
        get_application_field "${application}" '{.spec.source.path}'
    )"

    destination_namespace="$(
        get_application_field "${application}" '{.spec.destination.namespace}'
    )"

    sync_status="$(
        get_application_field "${application}" '{.status.sync.status}'
    )"

    health_status="$(
        get_application_field "${application}" '{.status.health.status}'
    )"

    revision="$(
        get_application_field "${application}" '{.status.sync.revision}'
    )"

    reconciled_at="$(
        get_application_field "${application}" '{.status.reconciledAt}'
    )"

    echo "Repository: ${repository:-not reported}"
    echo "Target revision: ${target_revision:-not reported}"
    echo "Source path: ${source_path:-not reported}"
    echo "Destination namespace: ${destination_namespace:-not reported}"
    echo "Current sync status: ${sync_status:-unknown}"
    echo "Current health status: ${health_status:-unknown}"
    echo "Current resolved revision: ${revision:-not reported}"
    echo "Last reconciled: ${reconciled_at:-not reported}"
}

print_operation_state() {
    local application="$1"

    local phase
    local message
    local started_at
    local finished_at
    local revision
    local initiated_by_username
    local initiated_by_automated

    phase="$(
        get_application_field \
            "${application}" \
            '{.status.operationState.phase}'
    )"

    message="$(
        get_application_field \
            "${application}" \
            '{.status.operationState.message}'
    )"

    started_at="$(
        get_application_field \
            "${application}" \
            '{.status.operationState.startedAt}'
    )"

    finished_at="$(
        get_application_field \
            "${application}" \
            '{.status.operationState.finishedAt}'
    )"

    revision="$(
        get_application_field \
            "${application}" \
            '{.status.operationState.syncResult.revision}'
    )"

    initiated_by_username="$(
        get_application_field \
            "${application}" \
            '{.status.operationState.operation.initiatedBy.username}'
    )"

    initiated_by_automated="$(
        get_application_field \
            "${application}" \
            '{.status.operationState.operation.initiatedBy.automated}'
    )"

    echo "Phase: ${phase:-not reported}"
    echo "Message: ${message:-not reported}"
    echo "Started at: ${started_at:-not reported}"
    echo "Finished at: ${finished_at:-not reported}"
    echo "Operation revision: ${revision:-not reported}"
    echo "Initiated by user: ${initiated_by_username:-not reported}"
    echo "Initiated automatically: ${initiated_by_automated:-false}"
}

print_operation_resource_results() {
    local application="$1"
    local resource_results

    resource_results="$(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='
{range .status.operationState.syncResult.resources[*]}
{.group}{"\t"}{.kind}{"\t"}{.namespace}{"\t"}{.name}{"\t"}{.status}{"\t"}{.hookPhase}{"\t"}{.message}{"\n"}
{end}' \
            2>/dev/null || true
    )"

    if [[ -z "${resource_results//[[:space:]]/}" ]]; then
        echo "No resource results are recorded for the last operation."
        return
    fi

    printf "%-25s %-24s %-20s %-42s %-12s %-12s %s\n" \
        "API GROUP" \
        "KIND" \
        "NAMESPACE" \
        "NAME" \
        "STATUS" \
        "HOOK PHASE" \
        "MESSAGE"

    printf "%-25s %-24s %-20s %-42s %-12s %-12s %s\n" \
        "-------------------------" \
        "------------------------" \
        "--------------------" \
        "------------------------------------------" \
        "------------" \
        "------------" \
        "-------"

    while IFS=$'\t' read -r \
        group \
        kind \
        namespace \
        name \
        status \
        hook_phase \
        message
    do
        [[ -z "${kind}" ]] && continue

        printf "%-25s %-24s %-20s %-42s %-12s %-12s %s\n" \
            "${group:-core}" \
            "${kind:-unknown}" \
            "${namespace:-cluster-scoped}" \
            "${name:-unknown}" \
            "${status:-unknown}" \
            "${hook_phase:-not reported}" \
            "${message:-}"
    done <<< "${resource_results}"
}

print_application_conditions() {
    local application="$1"
    local conditions

    conditions="$(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='
{range .status.conditions[*]}
{.type}{"\t"}{.lastTransitionTime}{"\t"}{.message}{"\n"}
{end}' \
            2>/dev/null || true
    )"

    if [[ -z "${conditions//[[:space:]]/}" ]]; then
        echo "No current Application conditions are reported."
        return
    fi

    while IFS=$'\t' read -r condition_type transition_time message
    do
        [[ -z "${condition_type}" ]] && continue

        echo "Type: ${condition_type}"
        echo "Last transition: ${transition_time:-not reported}"
        echo "Message: ${message:-not reported}"
        echo
    done <<< "${conditions}"
}

print_out_of_sync_resources() {
    local application="$1"
    local resources
    local found="false"

    resources="$(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='
{range .status.resources[*]}
{.group}{"\t"}{.kind}{"\t"}{.namespace}{"\t"}{.name}{"\t"}{.status}{"\t"}{.health.status}{"\n"}
{end}' \
            2>/dev/null || true
    )"

    if [[ -z "${resources//[[:space:]]/}" ]]; then
        echo "No managed resources are reported."
        return
    fi

    printf "%-25s %-25s %-20s %-45s %-12s %-12s\n" \
        "API GROUP" \
        "KIND" \
        "NAMESPACE" \
        "NAME" \
        "SYNC" \
        "HEALTH"

    while IFS=$'\t' read -r \
        group \
        kind \
        namespace \
        name \
        sync_status \
        health_status
    do
        [[ -z "${kind}" ]] && continue
        [[ "${sync_status}" != "OutOfSync" ]] && continue

        found="true"

        printf "%-25s %-25s %-20s %-45s %-12s %-12s\n" \
            "${group:-core}" \
            "${kind:-unknown}" \
            "${namespace:-cluster-scoped}" \
            "${name:-unknown}" \
            "${sync_status:-unknown}" \
            "${health_status:-not reported}"
    done <<< "${resources}"

    if [[ "${found}" == "false" ]]; then
        echo "No OutOfSync resources are currently reported."
    fi
}

print_deployment_history() {
    local application="$1"
    local history

    history="$(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='
{range .status.history[*]}
{.id}{"\t"}{.revision}{"\t"}{.deployedAt}{"\t"}{.source.targetRevision}{"\t"}{.source.path}{"\n"}
{end}' \
            2>/dev/null || true
    )"

    if [[ -z "${history//[[:space:]]/}" ]]; then
        echo "No deployment history is recorded."
        return
    fi

    printf "%-6s %-42s %-28s %-18s %s\n" \
        "ID" \
        "REVISION" \
        "DEPLOYED AT" \
        "TARGET REVISION" \
        "SOURCE PATH"

    while IFS=$'\t' read -r \
        history_id \
        revision \
        deployed_at \
        target_revision \
        source_path
    do
        [[ -z "${history_id}" ]] && continue

        printf "%-6s %-42s %-28s %-18s %s\n" \
            "${history_id}" \
            "${revision:-not reported}" \
            "${deployed_at:-not reported}" \
            "${target_revision:-not reported}" \
            "${source_path:-not reported}"
    done <<< "${history}"
}

print_application_events() {
    local application="$1"

    kubectl get events \
        --namespace "${ARGOCD_NAMESPACE}" \
        --field-selector \
"involvedObject.kind=Application,involvedObject.name=${application}" \
        --sort-by='.lastTimestamp' \
        2>&1 || true
}

print_header "Argo CD Sync and Health Diagnostics"

echo "Collection timestamp: $(date --iso-8601=seconds)"
echo "Kubernetes context: $(kubectl config current-context 2>/dev/null || true)"
echo "Argo CD namespace: ${ARGOCD_NAMESPACE}"
echo "Output file: ${OUTPUT_FILE}"

APPLICATION_NAMES="$(
    kubectl get applications.argoproj.io \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null || true
)"

if [[ -z "${APPLICATION_NAMES}" ]]; then
    print_header "Applications"
    echo "No Argo CD Applications were found."
else
    while IFS= read -r application
    do
        [[ -z "${application}" ]] && continue

        print_header "Application Diagnostics: ${application}"

        print_subheader "Current Application State"
        print_application_summary "${application}"

        print_subheader "Last Synchronization Operation"
        print_operation_state "${application}"

        print_subheader "Last Operation Resource Results"
        print_operation_resource_results "${application}"

        print_subheader "Current Application Conditions"
        print_application_conditions "${application}"

        print_subheader "Current OutOfSync Resources"
        print_out_of_sync_resources "${application}"

        print_subheader "Deployment History"
        print_deployment_history "${application}"

        print_subheader "Kubernetes Events for Application"
        print_application_events "${application}"

    done <<< "${APPLICATION_NAMES}"
fi

print_header "Diagnostics Summary"

echo "Applications inspected: $(
    printf '%s\n' "${APPLICATION_NAMES}" |
        sed '/^[[:space:]]*$/d' |
        wc -l
)"

echo "Diagnostics completed successfully."
echo "Generated output:"
echo "${OUTPUT_FILE}"
