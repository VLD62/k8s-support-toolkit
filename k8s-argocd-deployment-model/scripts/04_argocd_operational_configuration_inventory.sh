#!/usr/bin/env bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLSET_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
OUTPUT_DIR="${OUTPUT_DIR:-${TOOLSET_DIR}/output}"
OUTPUT_FILE="${OUTPUT_DIR}/04_argocd_operational_configuration_inventory_${TIMESTAMP}.txt"

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

resource_exists() {
    local resource_type="$1"
    local resource_name="$2"

    kubectl get "${resource_type}" \
        "${resource_name}" \
        --namespace "${ARGOCD_NAMESPACE}" \
        >/dev/null 2>&1
}

get_configmap_value() {
    local configmap="$1"
    local key="$2"

    kubectl get configmap \
        "${configmap}" \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output "jsonpath={.data.${key}}" \
        2>/dev/null || true
}

decode_secret_key() {
    local secret="$1"
    local key="$2"
    local encoded_value

    encoded_value="$(
        kubectl get secret \
            "${secret}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output "jsonpath={.data.${key}}" \
            2>/dev/null || true
    )"

    if [[ -z "${encoded_value}" ]]; then
        return 0
    fi

    printf '%s' "${encoded_value}" |
        base64 --decode 2>/dev/null || true
}

print_secret_data_keys() {
    local secret="$1"

    kubectl get secret \
        "${secret}" \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output go-template='
{{- range $key, $value := .data }}
{{ printf "%s\n" $key }}
{{- end }}' \
        2>/dev/null || true
}

print_configmap_data() {
    local configmap="$1"

    kubectl get configmap \
        "${configmap}" \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output go-template='
{{- range $key, $value := .data }}
{{ printf "%s=%s\n" $key $value }}
{{- end }}' \
        2>/dev/null || true
}

print_repository_secret() {
    local secret="$1"

    local repository_url
    local repository_type
    local repository_name
    local repository_project
    local enable_oci
    local insecure

    repository_url="$(decode_secret_key "${secret}" "url")"
    repository_type="$(decode_secret_key "${secret}" "type")"
    repository_name="$(decode_secret_key "${secret}" "name")"
    repository_project="$(decode_secret_key "${secret}" "project")"
    enable_oci="$(decode_secret_key "${secret}" "enableOCI")"
    insecure="$(decode_secret_key "${secret}" "insecure")"

    echo "Secret: ${secret}"
    echo "Repository URL: ${repository_url:-not reported}"
    echo "Repository type: ${repository_type:-not reported}"
    echo "Repository name: ${repository_name:-not reported}"
    echo "Restricted to project: ${repository_project:-not configured}"
    echo "OCI enabled: ${enable_oci:-false}"
    echo "TLS verification disabled: ${insecure:-false}"

    echo "Stored data keys:"

    print_secret_data_keys "${secret}" |
        sed 's/^/  - /'

    echo
    echo "Credential values were intentionally not collected."
}

print_cluster_secret() {
    local secret="$1"

    local cluster_name
    local cluster_server
    local project

    cluster_name="$(decode_secret_key "${secret}" "name")"
    cluster_server="$(decode_secret_key "${secret}" "server")"
    project="$(decode_secret_key "${secret}" "project")"

    echo "Secret: ${secret}"
    echo "Cluster name: ${cluster_name:-not reported}"
    echo "Cluster server: ${cluster_server:-not reported}"
    echo "Restricted to project: ${project:-not configured}"

    echo "Stored data keys:"

    print_secret_data_keys "${secret}" |
        sed 's/^/  - /'

    echo
    echo "Authentication and TLS values were intentionally not collected."
}

print_application_metadata() {
    local application="$1"

    print_header "Application Metadata: ${application}"

    echo "Created at: $(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.metadata.creationTimestamp}' \
            2>/dev/null || true
    )"

    echo "Generation: $(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.metadata.generation}' \
            2>/dev/null || true
    )"

    print_subheader "Finalizers"

    local finalizers

    finalizers="$(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{range .metadata.finalizers[*]}{.}{"\n"}{end}' \
            2>/dev/null || true
    )"

    if [[ -n "${finalizers}" ]]; then
        echo "${finalizers}"
    else
        echo "No finalizers configured."
    fi

    print_subheader "Labels"

    local labels

    labels="$(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output go-template='
{{- range $key, $value := .metadata.labels }}
{{ printf "%s=%s\n" $key $value }}
{{- end }}' \
            2>/dev/null || true
    )"

    if [[ -n "${labels}" ]]; then
        echo "${labels}"
    else
        echo "No labels configured."
    fi

    print_subheader "Annotation Keys"

    local annotations

    annotations="$(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output go-template='
{{- range $key, $value := .metadata.annotations }}
{{ printf "%s\n" $key }}
{{- end }}' \
            2>/dev/null || true
    )"

    if [[ -n "${annotations}" ]]; then
        echo "${annotations}"
    else
        echo "No annotations configured."
    fi

    print_subheader "Managed Fields"

    local managed_fields

    managed_fields="$(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='
{range .metadata.managedFields[*]}
Manager: {.manager}
Operation: {.operation}
API version: {.apiVersion}
Time: {.time}
---
{end}' \
            2>/dev/null || true
    )"

    if [[ -n "${managed_fields//[[:space:]]/}" ]]; then
        echo "${managed_fields}"
    else
        echo "No managed field information reported."
    fi

    print_subheader "Application Specification"

    kubectl get applications.argoproj.io \
        "${application}" \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output jsonpath='
Project: {.spec.project}
Repository: {.spec.source.repoURL}
Target revision: {.spec.source.targetRevision}
Path: {.spec.source.path}
Chart: {.spec.source.chart}
Destination server: {.spec.destination.server}
Destination cluster name: {.spec.destination.name}
Destination namespace: {.spec.destination.namespace}
' \
        2>/dev/null || true

    print_subheader "Sync Configuration"

    local automated

    automated="$(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.spec.syncPolicy.automated}' \
            2>/dev/null || true
    )"

    if [[ -n "${automated}" ]]; then
        echo "Automated sync: enabled"

        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='
Prune: {.spec.syncPolicy.automated.prune}
Self-heal: {.spec.syncPolicy.automated.selfHeal}
Allow empty: {.spec.syncPolicy.automated.allowEmpty}
' \
            2>/dev/null || true
    else
        echo "Automated sync: disabled"
    fi

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

    print_subheader "Ignore Differences Rules"

    local ignore_differences

    ignore_differences="$(
        kubectl get applications.argoproj.io \
            "${application}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='
{range .spec.ignoreDifferences[*]}
Group: {.group}
Kind: {.kind}
Name: {.name}
Namespace: {.namespace}
JSON pointers: {range .jsonPointers[*]}{.}{" "}{end}
JQ expressions: {range .jqPathExpressions[*]}{.}{" "}{end}
Managed fields managers: {range .managedFieldsManagers[*]}{.}{" "}{end}
---
{end}' \
            2>/dev/null || true
    )"

    if [[ -n "${ignore_differences//[[:space:]]/}" ]]; then
        echo "${ignore_differences}"
    else
        echo "No ignoreDifferences rules configured."
    fi
}

print_project_configuration() {
    local project="$1"

    print_header "AppProject Configuration: ${project}"

    echo "Description: $(
        kubectl get appprojects.argoproj.io \
            "${project}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.spec.description}' \
            2>/dev/null || true
    )"

    echo "Orphaned resource warnings: $(
        kubectl get appprojects.argoproj.io \
            "${project}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.spec.orphanedResources.warn}' \
            2>/dev/null || true
    )"

    echo "Project-scoped clusters only: $(
        kubectl get appprojects.argoproj.io \
            "${project}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.spec.permitOnlyProjectScopedClusters}' \
            2>/dev/null || true
    )"

    print_subheader "Source Repositories"

    local repositories

    repositories="$(
        kubectl get appprojects.argoproj.io \
            "${project}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{range .spec.sourceRepos[*]}{.}{"\n"}{end}' \
            2>/dev/null || true
    )"

    if [[ -n "${repositories}" ]]; then
        echo "${repositories}"
    else
        echo "No explicit source repositories listed."
    fi

    print_subheader "Destinations"

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

    print_subheader "Source Namespaces"

    local source_namespaces

    source_namespaces="$(
        kubectl get appprojects.argoproj.io \
            "${project}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{range .spec.sourceNamespaces[*]}{.}{"\n"}{end}' \
            2>/dev/null || true
    )"

    if [[ -n "${source_namespaces}" ]]; then
        echo "${source_namespaces}"
    else
        echo "No additional source namespaces configured."
    fi

    print_subheader "Synchronization Windows"

    local sync_windows

    sync_windows="$(
        kubectl get appprojects.argoproj.io \
            "${project}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='
{range .spec.syncWindows[*]}
Kind: {.kind}
Schedule: {.schedule}
Duration: {.duration}
Manual sync allowed: {.manualSync}
Applications: {range .applications[*]}{.}{" "}{end}
Namespaces: {range .namespaces[*]}{.}{" "}{end}
Clusters: {range .clusters[*]}{.}{" "}{end}
---
{end}' \
            2>/dev/null || true
    )"

    if [[ -n "${sync_windows//[[:space:]]/}" ]]; then
        echo "${sync_windows}"
    else
        echo "No synchronization windows configured."
    fi

    print_subheader "Project Roles"

    local project_roles

    project_roles="$(
        kubectl get appprojects.argoproj.io \
            "${project}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='
{range .spec.roles[*]}
Role: {.name}
Description: {.description}
Groups: {range .groups[*]}{.}{" "}{end}
Policies: {range .policies[*]}{.}{" "}{end}
---
{end}' \
            2>/dev/null || true
    )"

    if [[ -n "${project_roles//[[:space:]]/}" ]]; then
        echo "${project_roles}"
    else
        echo "No project-specific roles configured."
    fi
}

print_header "Argo CD Operational Configuration Inventory"

echo "Collection timestamp: $(date --iso-8601=seconds)"
echo "Kubernetes context: $(kubectl config current-context 2>/dev/null || true)"
echo "Argo CD namespace: ${ARGOCD_NAMESPACE}"
echo "Output file: ${OUTPUT_FILE}"

print_header "Argo CD Core Configuration"

if resource_exists configmap argocd-cm; then
    echo "Public URL: $(
        kubectl get configmap argocd-cm \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.data.url}' \
            2>/dev/null || true
    )"

    echo "Resource tracking method: $(
        kubectl get configmap argocd-cm \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.data.application\.resourceTrackingMethod}' \
            2>/dev/null || true
    )"

    echo "Instance label key: $(
        kubectl get configmap argocd-cm \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.data.application\.instanceLabelKey}' \
            2>/dev/null || true
    )"

    echo "Admin account enabled: $(
        kubectl get configmap argocd-cm \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.data.admin\.enabled}' \
            2>/dev/null || true
    )"

    OIDC_CONFIG="$(
        kubectl get configmap argocd-cm \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.data.oidc\.config}' \
            2>/dev/null || true
    )"

    DEX_CONFIG="$(
        kubectl get configmap argocd-cm \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.data.dex\.config}' \
            2>/dev/null || true
    )"

    if [[ -n "${OIDC_CONFIG}" ]]; then
        echo "OIDC configuration: present"
    else
        echo "OIDC configuration: not present"
    fi

    if [[ -n "${DEX_CONFIG}" ]]; then
        echo "Dex connector configuration: present"
    else
        echo "Dex connector configuration: not present"
    fi

    echo
    echo "Configured local account keys:"

    LOCAL_ACCOUNT_KEYS="$(
        kubectl get configmap argocd-cm \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output go-template='
{{- range $key, $value := .data }}
{{- if hasPrefix $key "accounts." }}
{{ printf "%s=%s\n" $key $value }}
{{- end }}
{{- end }}' \
            2>/dev/null || true
    )"

    if [[ -n "${LOCAL_ACCOUNT_KEYS}" ]]; then
        echo "${LOCAL_ACCOUNT_KEYS}"
    else
        echo "No additional local account keys found."
    fi
else
    echo "ConfigMap argocd-cm was not found."
fi

print_header "Argo CD Command Parameters"

if resource_exists configmap argocd-cmd-params-cm; then
    print_configmap_data argocd-cmd-params-cm
else
    echo "ConfigMap argocd-cmd-params-cm was not found."
fi

print_header "Argo CD RBAC Summary"

if resource_exists configmap argocd-rbac-cm; then
    POLICY_DEFAULT="$(
        kubectl get configmap argocd-rbac-cm \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.data.policy\.default}' \
            2>/dev/null || true
    )"

    SCOPES="$(
        kubectl get configmap argocd-rbac-cm \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.data.scopes}' \
            2>/dev/null || true
    )"

    POLICY_CSV="$(
        kubectl get configmap argocd-rbac-cm \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='{.data.policy\.csv}' \
            2>/dev/null || true
    )"

    echo "Default policy: ${POLICY_DEFAULT:-not configured}"
    echo "Identity scopes: ${SCOPES:-not configured}"

    echo
    echo "Permission rules:"

    PERMISSION_RULES="$(
        printf '%s\n' "${POLICY_CSV}" |
            awk -F',' '
                /^[[:space:]]*p[[:space:]]*,/ {
                    print
                }
            '
    )"

    if [[ -n "${PERMISSION_RULES}" ]]; then
        echo "${PERMISSION_RULES}"
    else
        echo "No explicit permission rules found."
    fi

    GROUP_MAPPING_COUNT="$(
        printf '%s\n' "${POLICY_CSV}" |
            awk '
                /^[[:space:]]*g[[:space:]]*,/ {
                    count++
                }
                END {
                    print count + 0
                }
            '
    )"

    echo
    echo "Identity-to-role mappings: ${GROUP_MAPPING_COUNT}"
    echo "Mapping identities were intentionally not printed."
else
    echo "ConfigMap argocd-rbac-cm was not found."
fi

print_header "Registered Repository Connections"

REPOSITORY_SECRETS="$(
    kubectl get secrets \
        --namespace "${ARGOCD_NAMESPACE}" \
        --selector 'argocd.argoproj.io/secret-type=repository' \
        --output jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null || true
)"

if [[ -z "${REPOSITORY_SECRETS}" ]]; then
    echo "No repository secrets found."
else
    while IFS= read -r repository_secret
    do
        [[ -z "${repository_secret}" ]] && continue

        print_subheader "Repository Connection"

        print_repository_secret "${repository_secret}"
    done <<< "${REPOSITORY_SECRETS}"
fi

print_header "Registered Cluster Connections"

CLUSTER_SECRETS="$(
    kubectl get secrets \
        --namespace "${ARGOCD_NAMESPACE}" \
        --selector 'argocd.argoproj.io/secret-type=cluster' \
        --output jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null || true
)"

if [[ -z "${CLUSTER_SECRETS}" ]]; then
    echo "No external cluster connection secrets found."
    echo "Applications may be using the in-cluster Kubernetes API."
else
    while IFS= read -r cluster_secret
    do
        [[ -z "${cluster_secret}" ]] && continue

        print_subheader "Cluster Connection"

        print_cluster_secret "${cluster_secret}"
    done <<< "${CLUSTER_SECRETS}"
fi

print_header "Argo CD Ingress Configuration"

INGRESS_NAMES="$(
    kubectl get ingress \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null || true
)"

if [[ -z "${INGRESS_NAMES}" ]]; then
    echo "No Kubernetes Ingress resources found."
else
    while IFS= read -r ingress
    do
        [[ -z "${ingress}" ]] && continue

        print_subheader "Ingress: ${ingress}"

        kubectl get ingress \
            "${ingress}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output jsonpath='
Ingress class: {.spec.ingressClassName}
{range .spec.rules[*]}
Host: {.host}
{range .http.paths[*]}
Path: {.path}
Path type: {.pathType}
Backend service: {.backend.service.name}
Backend port name: {.backend.service.port.name}
Backend port number: {.backend.service.port.number}
{end}
{end}
TLS:
{range .spec.tls[*]}
Secret: {.secretName}
Hosts: {range .hosts[*]}{.}{" "}{end}
{end}
' \
            2>/dev/null || true

        echo
        echo "Annotations:"

        kubectl get ingress \
            "${ingress}" \
            --namespace "${ARGOCD_NAMESPACE}" \
            --output go-template='
{{- range $key, $value := .metadata.annotations }}
{{ printf "%s=%s\n" $key $value }}
{{- end }}' \
            2>/dev/null || true
    done <<< "${INGRESS_NAMES}"
fi

APPLICATION_NAMES="$(
    kubectl get applications.argoproj.io \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null || true
)"

if [[ -z "${APPLICATION_NAMES}" ]]; then
    print_header "Application Metadata"
    echo "No Argo CD Applications found."
else
    while IFS= read -r application
    do
        [[ -z "${application}" ]] && continue

        print_application_metadata "${application}"
    done <<< "${APPLICATION_NAMES}"
fi

PROJECT_NAMES="$(
    kubectl get appprojects.argoproj.io \
        --namespace "${ARGOCD_NAMESPACE}" \
        --output jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null || true
)"

if [[ -z "${PROJECT_NAMES}" ]]; then
    print_header "AppProject Configuration"
    echo "No Argo CD AppProjects found."
else
    while IFS= read -r project
    do
        [[ -z "${project}" ]] && continue

        print_project_configuration "${project}"
    done <<< "${PROJECT_NAMES}"
fi

print_header "Inventory Summary"

echo "Applications inspected: $(
    printf '%s\n' "${APPLICATION_NAMES}" |
        sed '/^[[:space:]]*$/d' |
        wc -l
)"

echo "Projects inspected: $(
    printf '%s\n' "${PROJECT_NAMES}" |
        sed '/^[[:space:]]*$/d' |
        wc -l
)"

echo "Repository connections inspected: $(
    printf '%s\n' "${REPOSITORY_SECRETS}" |
        sed '/^[[:space:]]*$/d' |
        wc -l
)"

echo "External cluster connections inspected: $(
    printf '%s\n' "${CLUSTER_SECRETS}" |
        sed '/^[[:space:]]*$/d' |
        wc -l
)"

echo
echo "Secret credential values were not collected."
echo "Operational configuration inventory completed successfully."
echo "Generated output:"
echo "${OUTPUT_FILE}"
