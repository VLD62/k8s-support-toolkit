#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLSET_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
OUTPUT_DIR="${OUTPUT_DIR:-${TOOLSET_DIR}/output}"
OUTPUT_FILE="${OUTPUT_DIR}/02_argocd_applications_projects_inventory_${TIMESTAMP}.txt"

ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"

mkdir -p "${OUTPUT_DIR}"

exec > >(tee "${OUTPUT_FILE}") 2>&1

print_header() {
    local title="$1"

    echo
    echo "======================================================================"
    echo "${title}"
    echo "======================================================================"
}

print_subheader() {
    local title="$1"

    echo
    echo "----------------------------------------------------------------------"
    echo "${title}"
    echo "----------------------------------------------------------------------"
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

get_application_field() {
    local application="$1"
    local jsonpath="$2"

    kubectl get applications.argoproj.io \
        "${application}" \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output "jsonpath=${jsonpath}" \
        2>/dev/null || true
}

get_project_field() {
    local project="$1"
    local jsonpath="$2"

    kubectl get appprojects.argoproj.io \
        "${project}" \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output "jsonpath=${jsonpath}" \
        2>/dev/null || true
}

sanitize_repository_url() {
    sed -E \
        -e 's#(https?://)[^/@]+@#\1***@#' \
        -e 's#(ssh://)[^/@]+@#\1***@#'
}

print_application_source() {
    local application="$1"

    local repository
    local target_revision
    local path
    local chart
    local source_type

    repository="$(
        get_application_field \
            "${application}" \
            '{.spec.source.repoURL}' |
            sanitize_repository_url
    )"

    target_revision="$(
        get_application_field \
            "${application}" \
            '{.spec.source.targetRevision}'
    )"

    path="$(
        get_application_field \
            "${application}" \
            '{.spec.source.path}'
    )"

    chart="$(
        get_application_field \
            "${application}" \
            '{.spec.source.chart}'
    )"

    source_type="$(
        get_application_field \
            "${application}" \
            '{.status.sourceType}'
    )"

    if [[ -n "${repository}" ]]; then
        echo "Source mode: single source"
        echo "Repository: ${repository}"
        echo "Target revision: ${target_revision:-not specified}"
        echo "Source path: ${path:-not specified}"
        echo "Helm chart: ${chart:-not specified}"
        echo "Detected source type: ${source_type:-not reported}"
        return
    fi

    local multi_source_output

    multi_source_output="$(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='
{range .spec.sources[*]}
Repository: {.repoURL}
Target revision: {.targetRevision}
Path: {.path}
Chart: {.chart}
Reference: {.ref}
---
{end}' \
            2>/dev/null |
            sanitize_repository_url
    )"

    if [[ -n "${multi_source_output//[[:space:]]/}" ]]; then
        echo "Source mode: multiple sources"
        echo "${multi_source_output}"
    else
        echo "Source information could not be determined."
    fi
}

print_application_sync_policy() {
    local application="$1"

    local automated
    local prune
    local self_heal
    local allow_empty
    local retry_limit

    automated="$(
        get_application_field \
            "${application}" \
            '{.spec.syncPolicy.automated}'
    )"

    prune="$(
        get_application_field \
            "${application}" \
            '{.spec.syncPolicy.automated.prune}'
    )"

    self_heal="$(
        get_application_field \
            "${application}" \
            '{.spec.syncPolicy.automated.selfHeal}'
    )"

    allow_empty="$(
        get_application_field \
            "${application}" \
            '{.spec.syncPolicy.automated.allowEmpty}'
    )"

    retry_limit="$(
        get_application_field \
            "${application}" \
            '{.spec.syncPolicy.retry.limit}'
    )"

    if [[ -n "${automated}" ]]; then
        echo "Automated synchronization: enabled"
        echo "Automatic pruning: ${prune:-false}"
        echo "Automatic self-healing: ${self_heal:-false}"
        echo "Allow empty application: ${allow_empty:-false}"
    else
        echo "Automated synchronization: disabled or not configured"
    fi

    echo "Retry limit: ${retry_limit:-not configured}"

    echo
    echo "Sync options:"

    local sync_options

    sync_options="$(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{range .spec.syncPolicy.syncOptions[*]}{.}{"\n"}{end}' \
            2>/dev/null || true
    )"

    if [[ -n "${sync_options}" ]]; then
        echo "${sync_options}"
    else
        echo "No explicit sync options configured."
    fi
}

print_application_managed_resources() {
    local application="$1"

    local resources

    resources="$(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='
{range .status.resources[*]}
{.group}{"|"}{.kind}{"|"}{.namespace}{"|"}{.name}{"|"}{.status}{"|"}{.health.status}{"\n"}
{end}' \
            2>/dev/null || true
    )"

    if [[ -z "${resources//[[:space:]]/}" ]]; then
        echo "No managed resources reported in Application status."
        return
    fi

    printf "%-30s %-28s %-28s %-45s %-12s %-12s\n" \
        "API GROUP" \
        "KIND" \
        "NAMESPACE" \
        "NAME" \
        "SYNC" \
        "HEALTH"

    printf "%-30s %-28s %-28s %-45s %-12s %-12s\n" \
        "------------------------------" \
        "----------------------------" \
        "----------------------------" \
        "---------------------------------------------" \
        "------------" \
        "------------"

    while IFS='|' read -r \
        resource_group \
        resource_kind \
        resource_namespace \
        resource_name \
        resource_sync \
        resource_health
    do
        [[ -z "${resource_kind}" ]] && continue

        printf "%-30s %-28s %-28s %-45s %-12s %-12s\n" \
            "${resource_group:-core}" \
            "${resource_kind:-unknown}" \
            "${resource_namespace:-cluster-scoped}" \
            "${resource_name:-unknown}" \
            "${resource_sync:-unknown}" \
            "${resource_health:-not reported}"
    done <<< "${resources}"
}

print_project_details() {
    local project="$1"

    print_header "Argo CD Project: ${project}"

    echo "Description: $(
        get_project_field \
            "${project}" \
            '{.spec.description}'
    )"

    print_subheader "Allowed Source Repositories"

    local source_repositories

    source_repositories="$(
        kubectl get appprojects.argoproj.io \
            "${project}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{range .spec.sourceRepos[*]}{.}{"\n"}{end}' \
            2>/dev/null |
            sanitize_repository_url
    )"

    if [[ -n "${source_repositories}" ]]; then
        echo "${source_repositories}"
    else
        echo "No source repositories explicitly configured."
    fi

    print_subheader "Allowed Deployment Destinations"

    local destinations

    destinations="$(
        kubectl get appprojects.argoproj.io \
            "${project}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='
{range .spec.destinations[*]}
Server: {.server}
Cluster name: {.name}
Namespace: {.namespace}
---
{end}' \
            2>/dev/null || true
    )"

    if [[ -n "${destinations//[[:space:]]/}" ]]; then
        echo "${destinations}"
    else
        echo "No destinations explicitly configured."
    fi

    print_subheader "Project Roles"

    local roles

    roles="$(
        kubectl get appprojects.argoproj.io \
            "${project}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='
{range .spec.roles[*]}
Role: {.name}
Description: {.description}
Groups: {range .groups[*]}{.}{" "}{end}
---
{end}' \
            2>/dev/null || true
    )"

    if [[ -n "${roles//[[:space:]]/}" ]]; then
        echo "${roles}"
    else
        echo "No project-specific roles configured."
    fi

    print_subheader "Project Resource Permissions"

    echo "Cluster resource whitelist:"

    kubectl get appprojects.argoproj.io \
        "${project}" \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output jsonpath='
{range .spec.clusterResourceWhitelist[*]}
Group: {.group}, Kind: {.kind}
{end}' \
        2>/dev/null || true

    echo
    echo "Cluster resource blacklist:"

    kubectl get appprojects.argoproj.io \
        "${project}" \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output jsonpath='
{range .spec.clusterResourceBlacklist[*]}
Group: {.group}, Kind: {.kind}
{end}' \
        2>/dev/null || true

    echo
    echo "Namespace resource whitelist:"

    kubectl get appprojects.argoproj.io \
        "${project}" \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output jsonpath='
{range .spec.namespaceResourceWhitelist[*]}
Group: {.group}, Kind: {.kind}
{end}' \
        2>/dev/null || true

    echo
    echo "Namespace resource blacklist:"

    kubectl get appprojects.argoproj.io \
        "${project}" \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output jsonpath='
{range .spec.namespaceResourceBlacklist[*]}
Group: {.group}, Kind: {.kind}
{end}' \
        2>/dev/null || true
}

print_header "Argo CD Applications and Projects Inventory"

echo "Collection timestamp: $(date --iso-8601=seconds)"
echo "Kubernetes context: $(kubectl config current-context 2>/dev/null || true)"
echo "Argo CD namespace: ${ARGOCD_NAMESPACE}"
echo "Output file: ${OUTPUT_FILE}"

run_command \
    "Application Summary" \
    kubectl get applications.argoproj.io \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output custom-columns='NAME:.metadata.name,PROJECT:.spec.project,SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision,DESTINATION:.spec.destination.namespace'

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

        print_header "Argo CD Application: ${application}"

        project="$(
            get_application_field \
                "${application}" \
                '{.spec.project}'
        )"

        destination_server="$(
            get_application_field \
                "${application}" \
                '{.spec.destination.server}'
        )"

        destination_name="$(
            get_application_field \
                "${application}" \
                '{.spec.destination.name}'
        )"

        destination_namespace="$(
            get_application_field \
                "${application}" \
                '{.spec.destination.namespace}'
        )"

        sync_status="$(
            get_application_field \
                "${application}" \
                '{.status.sync.status}'
        )"

        health_status="$(
            get_application_field \
                "${application}" \
                '{.status.health.status}'
        )"

        revision="$(
            get_application_field \
                "${application}" \
                '{.status.sync.revision}'
        )"

        reconciled_at="$(
            get_application_field \
                "${application}" \
                '{.status.reconciledAt}'
        )"

        operation_phase="$(
            get_application_field \
                "${application}" \
                '{.status.operationState.phase}'
        )"

        echo "Project: ${project:-default}"
        echo "Sync status: ${sync_status:-unknown}"
        echo "Health status: ${health_status:-unknown}"
        echo "Current revision: ${revision:-not reported}"
        echo "Last reconciled: ${reconciled_at:-not reported}"
        echo "Last operation phase: ${operation_phase:-not reported}"

        print_subheader "Deployment Destination"

        echo "Destination server: ${destination_server:-not specified}"
        echo "Destination cluster name: ${destination_name:-not specified}"
        echo "Destination namespace: ${destination_namespace:-not specified}"

        print_subheader "Git or Chart Source"

        print_application_source "${application}"

        print_subheader "Synchronization Policy"

        print_application_sync_policy "${application}"

        print_subheader "Managed Kubernetes Resources"

        print_application_managed_resources "${application}"

    done <<< "${APPLICATION_NAMES}"
fi

PROJECT_NAMES="$(
    kubectl get appprojects.argoproj.io \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null || true
)"

if [[ -z "${PROJECT_NAMES}" ]]; then
    print_header "Projects"

    echo "No Argo CD Projects were found."
else
    while IFS= read -r project
    do
        [[ -z "${project}" ]] && continue

        print_project_details "${project}"
    done <<< "${PROJECT_NAMES}"
fi

run_command \
    "ApplicationSet Summary" \
    kubectl get applicationsets.argoproj.io \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output wide

print_header "Inventory Summary"

echo "Applications discovered: $(
    printf '%s\n' "${APPLICATION_NAMES}" |
        sed '/^[[:space:]]*$/d' |
        wc -l
)"

echo "Projects discovered: $(
    printf '%s\n' "${PROJECT_NAMES}" |
        sed '/^[[:space:]]*$/d' |
        wc -l
)"

echo "Inventory completed successfully."
echo "Generated output:"
echo "${OUTPUT_FILE}"
