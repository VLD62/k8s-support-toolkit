#!/usr/bin/env bash

set -uo pipefail

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "${SCRIPT_DIR}")"
OUTPUT_DIR="${1:-${MODULE_DIR}/outputs/authentication_authorization_inventory_${TIMESTAMP}}"

mkdir -p "${OUTPUT_DIR}"

LOG_FILE="${OUTPUT_DIR}/00_authentication_authorization_execution.log"
STATUS_FILE="${OUTPUT_DIR}/00_authentication_authorization_status.md"

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

collect_apiserver_auth_flags() {
    local pods=()

    mapfile -t pods < <(
        kubectl get pods --namespace kube-system -o name 2>/dev/null \
            | grep '^pod/kube-apiserver-' || true
    )

    if [[ ${#pods[@]} -eq 0 ]]; then
        echo "No kube-apiserver Pod was visible through the Kubernetes API."
        return 0
    fi

    for pod in "${pods[@]}"; do
        echo "## ${pod}"
        echo

        kubectl get "${pod}" --namespace kube-system \
            -o jsonpath='{range .spec.containers[*]}Container: {.name}{"\n"}{range .command[*]}{.}{"\n"}{end}{range .args[*]}{.}{"\n"}{end}{end}' \
            | grep -E -- '^(Container:|--authorization-|--authentication-|--anonymous-auth|--client-ca-file|--oidc-|--requestheader-|--service-account-)' \
            || true

        echo
    done
}

collect_keystone_workload_summary() {
    kubectl get deployment,statefulset,daemonset,pod,service \
        --namespace kube-system \
        --selector app.kubernetes.io/name=k8s-keystone-auth \
        -o wide

    echo
    echo "## Deployment image and ServiceAccount"
    echo

    kubectl get deployments \
        --namespace kube-system \
        --selector app.kubernetes.io/name=k8s-keystone-auth \
        -o custom-columns='NAME:.metadata.name,SERVICEACCOUNT:.spec.template.spec.serviceAccountName,IMAGES:.spec.template.spec.containers[*].image'
}

collect_keystone_container_arguments() {
    local workloads=()

    mapfile -t workloads < <(
        kubectl get deployments,statefulsets,daemonsets \
            --namespace kube-system \
            --selector app.kubernetes.io/name=k8s-keystone-auth \
            -o name 2>/dev/null
    )

    if [[ ${#workloads[@]} -eq 0 ]]; then
        echo "No k8s-keystone-auth workload was found with the expected label."
        return 0
    fi

    for workload in "${workloads[@]}"; do
        echo "## ${workload}"
        echo

        kubectl get "${workload}" --namespace kube-system \
            -o jsonpath='{range .spec.template.spec.containers[*]}Container: {.name}{"\n"}Image: {.image}{"\n"}{range .command[*]}Command: {.}{"\n"}{end}{range .args[*]}Argument: {.}{"\n"}{end}{"\n"}{end}'

        echo
    done
}

collect_keystone_configmap_keys() {
    python3 <<'PY'
import json
import subprocess

command = [
    "kubectl",
    "get",
    "configmaps",
    "--namespace",
    "kube-system",
    "-o",
    "json",
]

data = json.loads(subprocess.check_output(command, text=True))
matched = []

for item in data.get("items", []):
    metadata = item.get("metadata", {})
    name = metadata.get("name", "")
    labels = metadata.get("labels", {}) or {}

    if (
        "keystone" not in name.lower()
        and labels.get("app.kubernetes.io/name") != "k8s-keystone-auth"
    ):
        continue

    matched.append(item)

if not matched:
    print("No matching k8s-keystone-auth ConfigMaps were found.")
else:
    for item in matched:
        metadata = item.get("metadata", {})
        data_keys = sorted((item.get("data") or {}).keys())
        binary_keys = sorted((item.get("binaryData") or {}).keys())

        print(
            f"ConfigMap: "
            f"{metadata.get('namespace', 'kube-system')}/"
            f"{metadata.get('name', '')}"
        )

        print("Data keys:")

        for key in data_keys:
            print(f"  - {key}")

        print("Binary data keys:")

        for key in binary_keys:
            print(f"  - {key}")

        print()
PY
}

collect_user_group_subjects() {
    python3 <<'PY'
import json
import subprocess


def kubectl_json(arguments):
    return json.loads(
        subprocess.check_output(
            ["kubectl", *arguments, "-o", "json"],
            text=True,
        )
    )


def rows_for(bindings, binding_scope):
    rows = []

    for binding in bindings.get("items", []):
        metadata = binding.get("metadata", {})
        role_ref = binding.get("roleRef", {})

        for subject in binding.get("subjects", []) or []:
            if subject.get("kind") not in {"User", "Group"}:
                continue

            rows.append(
                {
                    "scope": binding_scope,
                    "namespace": metadata.get("namespace", "-"),
                    "binding": metadata.get("name", ""),
                    "role_kind": role_ref.get("kind", ""),
                    "role": role_ref.get("name", ""),
                    "subject_kind": subject.get("kind", ""),
                    "subject": subject.get("name", ""),
                }
            )

    return rows


rows = []

rows.extend(
    rows_for(
        kubectl_json(["get", "clusterrolebindings"]),
        "cluster",
    )
)

rows.extend(
    rows_for(
        kubectl_json(
            ["get", "rolebindings", "--all-namespaces"]
        ),
        "namespace",
    )
)

headers = [
    "SCOPE",
    "NAMESPACE",
    "BINDING",
    "ROLE_KIND",
    "ROLE",
    "SUBJECT_KIND",
    "SUBJECT",
]

print("\t".join(headers))

for row in sorted(
    rows,
    key=lambda item: (
        item["scope"],
        item["namespace"],
        item["binding"],
        item["subject"],
    ),
):
    print(
        "\t".join(
            [
                row["scope"],
                row["namespace"],
                row["binding"],
                row["role_kind"],
                row["role"],
                row["subject_kind"],
                row["subject"],
            ]
        )
    )
PY
}

collect_non_system_user_group_subjects() {
    python3 <<'PY'
import json
import subprocess


def kubectl_json(arguments):
    return json.loads(
        subprocess.check_output(
            ["kubectl", *arguments, "-o", "json"],
            text=True,
        )
    )


found = False

binding_queries = [
    (
        "ClusterRoleBinding",
        ["get", "clusterrolebindings"],
    ),
    (
        "RoleBinding",
        ["get", "rolebindings", "--all-namespaces"],
    ),
]

for binding_kind, arguments in binding_queries:
    data = kubectl_json(arguments)

    for binding in data.get("items", []):
        metadata = binding.get("metadata", {})
        role_ref = binding.get("roleRef", {})

        for subject in binding.get("subjects", []) or []:
            if subject.get("kind") not in {"User", "Group"}:
                continue

            subject_name = subject.get("name", "")

            if (
                subject_name.startswith("system:")
                or subject_name.startswith("kubeadm:")
            ):
                continue

            found = True

            print(
                f"{binding_kind}: "
                f"{metadata.get('namespace', '-')}/"
                f"{metadata.get('name', '')} -> "
                f"{role_ref.get('kind', '')}/"
                f"{role_ref.get('name', '')} -> "
                f"{subject.get('kind', '')}/"
                f"{subject_name}"
            )

if not found:
    print(
        "No non-system User or Group subjects were found "
        "in Kubernetes RoleBindings or ClusterRoleBindings."
    )
PY
}

if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERROR: kubectl is not installed or is not available in PATH."
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required for subject mapping."
    exit 1
fi

log "Starting Kubernetes authentication and authorization inventory"
log "Output directory: ${OUTPUT_DIR}"

run_check \
    "Current Kubernetes identity" \
    "01_current_identity.txt" \
    kubectl auth whoami

run_check \
    "Current identity effective permissions" \
    "02_current_identity_permissions.txt" \
    kubectl auth can-i --list

run_check \
    "Kubernetes API server authentication and authorization flags" \
    "03_apiserver_authentication_authorization_flags.txt" \
    collect_apiserver_auth_flags

run_check \
    "Current identity impersonation permissions" \
    "04_impersonation_permission_checks.txt" \
    bash -c '
        checks=(
            "impersonate users"
            "impersonate groups"
            "impersonate serviceaccounts"
            "impersonate userextras.authentication.k8s.io"
        )

        for check in "${checks[@]}"; do
            printf "%-80s" "kubectl auth can-i ${check}"
            kubectl auth can-i ${check}
        done
    '

run_check \
    "k8s-keystone-auth workload and Service summary" \
    "05_keystone_auth_workload_summary.txt" \
    collect_keystone_workload_summary

run_check \
    "k8s-keystone-auth container commands and arguments" \
    "06_keystone_auth_container_arguments.txt" \
    collect_keystone_container_arguments

run_check \
    "k8s-keystone-auth ConfigMap names and data keys" \
    "07_keystone_auth_configmap_keys.txt" \
    collect_keystone_configmap_keys

run_check \
    "k8s-keystone-auth ClusterRole" \
    "08_keystone_auth_clusterrole.yaml" \
    kubectl get clusterrole system:k8s-keystone-auth -o yaml

run_check \
    "k8s-keystone-auth ClusterRoleBinding" \
    "09_keystone_auth_clusterrolebinding.yaml" \
    kubectl get clusterrolebinding system:k8s-keystone-auth -o yaml

run_check \
    "User and Group subject binding inventory" \
    "10_user_group_subject_bindings.tsv" \
    collect_user_group_subjects

run_check \
    "Non-system User and Group subjects" \
    "11_non_system_user_group_subjects.txt" \
    collect_non_system_user_group_subjects

{
    echo "# Kubernetes Authentication and Authorization Inventory Status"
    echo
    echo "- Generated: $(date --iso-8601=seconds)"
    echo "- Kubernetes context: $(kubectl config current-context 2>/dev/null || echo unavailable)"
    echo "- Successful checks: ${SUCCESSFUL_CHECKS}"
    echo "- Failed or access-denied checks: ${FAILED_CHECKS}"
    echo "- Output directory: \`${OUTPUT_DIR}\`"
    echo
    echo "## Security"
    echo
    echo "The script does not request Secret values, tokens, client certificates, or kubeconfig credentials."
    echo
    echo "Container arguments, internal identity-provider names, role subjects, and ConfigMap key names should still be handled as operationally sensitive information."
} >"${STATUS_FILE}"

log "Authentication and authorization inventory completed"
log "Successful checks: ${SUCCESSFUL_CHECKS}"
log "Failed or access-denied checks: ${FAILED_CHECKS}"
log "Status file: ${STATUS_FILE}"

echo
echo "Authentication and authorization inventory completed."
echo "Results: ${OUTPUT_DIR}"
