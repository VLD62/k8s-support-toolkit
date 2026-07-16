#!/usr/bin/env bash

set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"

OUTPUT_DIR="${OUTPUT_DIR:-./outputs}"
OUTPUT_FILE="${OUTPUT_DIR}/03_pvc_workload_mapping_${TIMESTAMP}.txt"

mkdir -p "${OUTPUT_DIR}"

USED_PVCS_FILE="$(mktemp)"
trap 'rm -f "${USED_PVCS_FILE}"' EXIT

print_separator() {
    printf '%*s\n' 120 '' | tr ' ' '='
}

print_section() {
    echo
    print_separator
    echo "$1"
    print_separator
}

run_command() {
    local description="$1"
    shift

    echo
    echo "\$ $*"
    echo

    if ! "$@" 2>&1; then
        echo
        echo "[WARNING] Unable to collect: ${description}"
    fi
}

check_dependency() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "[ERROR] Required command not found: $1"
        exit 1
    fi
}

resolve_workload_owner() {
    local namespace="$1"
    local owner_kind="$2"
    local owner_name="$3"

    if [[ -z "${owner_kind}" || -z "${owner_name}" ]]; then
        echo "StandalonePod"
        return
    fi

    case "${owner_kind}" in
        ReplicaSet)
            local deployment

            deployment="$(
                kubectl get replicaset "${owner_name}" \
                    --namespace "${namespace}" \
                    -o jsonpath='{range .metadata.ownerReferences[?(@.kind=="Deployment")]}{.name}{end}' \
                    2>/dev/null
            )"

            if [[ -n "${deployment}" ]]; then
                echo "Deployment/${deployment}"
            else
                echo "ReplicaSet/${owner_name}"
            fi
            ;;

        Job)
            local cronjob

            cronjob="$(
                kubectl get job "${owner_name}" \
                    --namespace "${namespace}" \
                    -o jsonpath='{range .metadata.ownerReferences[?(@.kind=="CronJob")]}{.name}{end}' \
                    2>/dev/null
            )"

            if [[ -n "${cronjob}" ]]; then
                echo "CronJob/${cronjob}"
            else
                echo "Job/${owner_name}"
            fi
            ;;

        StatefulSet|DaemonSet|Deployment)
            echo "${owner_kind}/${owner_name}"
            ;;

        *)
            echo "${owner_kind}/${owner_name}"
            ;;
    esac
}

collect_pod_pvc_mapping() {
    local namespace
    local pod
    local phase
    local node
    local owner_kind
    local owner_name

    while IFS=$'\t' read -r \
        namespace \
        pod \
        phase \
        node \
        owner_kind \
        owner_name; do

        [[ -z "${namespace}" || -z "${pod}" ]] && continue

        local workload
        workload="$(
            resolve_workload_owner \
                "${namespace}" \
                "${owner_kind}" \
                "${owner_name}"
        )"

        local volume_name
        local claim_name

        while IFS=$'\t' read -r volume_name claim_name; do
            [[ -z "${volume_name}" || -z "${claim_name}" ]] && continue

            printf '%s/%s\n' \
                "${namespace}" \
                "${claim_name}" >> "${USED_PVCS_FILE}"

            local pvc_status
            local storage_class
            local requested_capacity
            local bound_volume

            pvc_status="$(
                kubectl get pvc "${claim_name}" \
                    --namespace "${namespace}" \
                    -o jsonpath='{.status.phase}' \
                    2>/dev/null ||
                    true
            )"

            storage_class="$(
                kubectl get pvc "${claim_name}" \
                    --namespace "${namespace}" \
                    -o jsonpath='{.spec.storageClassName}' \
                    2>/dev/null ||
                    true
            )"

            requested_capacity="$(
                kubectl get pvc "${claim_name}" \
                    --namespace "${namespace}" \
                    -o jsonpath='{.spec.resources.requests.storage}' \
                    2>/dev/null ||
                    true
            )"

            bound_volume="$(
                kubectl get pvc "${claim_name}" \
                    --namespace "${namespace}" \
                    -o jsonpath='{.spec.volumeName}' \
                    2>/dev/null ||
                    true
            )"

            echo
            echo "PVC: ${namespace}/${claim_name}"
            echo "Pod: ${pod}"
            echo "Pod phase: ${phase:-Unknown}"
            echo "Node: ${node:-Unscheduled}"
            echo "Workload: ${workload}"
            echo "Pod volume name: ${volume_name}"
            echo "PVC status: ${pvc_status:-NotFound}"
            echo "StorageClass: ${storage_class:-NotSet}"
            echo "Requested capacity: ${requested_capacity:-Unknown}"
            echo "Bound volume: ${bound_volume:-NotBound}"
            echo "Container mounts:"

            local mounts_found="false"
            local container
            local mount_name
            local mount_path
            local read_only

            while IFS=$'\t' read -r \
                container \
                mount_name \
                mount_path \
                read_only; do

                [[ "${mount_name}" != "${volume_name}" ]] && continue

                mounts_found="true"

                echo "  - container=${container}" \
                    "path=${mount_path:-Unknown}" \
                    "readOnly=${read_only:-false}"

            done < <(
                kubectl get pod "${pod}" \
                    --namespace "${namespace}" \
                    -o go-template='{{range .spec.containers}}{{ $container := .name }}{{range .volumeMounts}}{{printf "%s\t%s\t%s\t%t\n" $container .name .mountPath .readOnly}}{{end}}{{end}}' \
                    2>/dev/null
            )

            if [[ "${mounts_found}" == "false" ]]; then
                echo "  - No regular container mount found."
                echo "    The volume may be used by an init container or declared but not mounted."
            fi

            local init_mounts_found="false"

            while IFS=$'\t' read -r \
                container \
                mount_name \
                mount_path \
                read_only; do

                [[ "${mount_name}" != "${volume_name}" ]] && continue

                if [[ "${init_mounts_found}" == "false" ]]; then
                    echo "Init container mounts:"
                    init_mounts_found="true"
                fi

                echo "  - container=${container}" \
                    "path=${mount_path:-Unknown}" \
                    "readOnly=${read_only:-false}"

            done < <(
                kubectl get pod "${pod}" \
                    --namespace "${namespace}" \
                    -o go-template='{{range .spec.initContainers}}{{ $container := .name }}{{range .volumeMounts}}{{printf "%s\t%s\t%s\t%t\n" $container .name .mountPath .readOnly}}{{end}}{{end}}' \
                    2>/dev/null
            )

            echo "------------------------------------------------------------"

        done < <(
            kubectl get pod "${pod}" \
                --namespace "${namespace}" \
                -o jsonpath='{range .spec.volumes[?(@.persistentVolumeClaim)]}{.name}{"\t"}{.persistentVolumeClaim.claimName}{"\n"}{end}' \
                2>/dev/null
        )

    done < <(
        kubectl get pods --all-namespaces \
            -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.nodeName}{"\t"}{.metadata.ownerReferences[0].kind}{"\t"}{.metadata.ownerReferences[0].name}{"\n"}{end}' \
            2>/dev/null
    )
}

collect_statefulset_claim_templates() {
    local namespace
    local statefulset

    while IFS=$'\t' read -r namespace statefulset; do
        [[ -z "${namespace}" || -z "${statefulset}" ]] && continue

        echo
        echo "StatefulSet: ${namespace}/${statefulset}"
        echo "------------------------------------------------------------"

        local templates

        templates="$(
            kubectl get statefulset "${statefulset}" \
                --namespace "${namespace}" \
                -o jsonpath='{range .spec.volumeClaimTemplates[*]}Name: {.metadata.name}{"\n"}StorageClass: {.spec.storageClassName}{"\n"}Requested capacity: {.spec.resources.requests.storage}{"\n"}Access modes: {.spec.accessModes}{"\n---\n"}{end}' \
                2>/dev/null
        )"

        if [[ -n "${templates}" ]]; then
            printf '%s\n' "${templates}"
        else
            echo "No volumeClaimTemplates configured."
        fi

    done < <(
        kubectl get statefulsets --all-namespaces \
            -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' \
            2>/dev/null
    )
}

collect_unreferenced_pvcs() {
    sort -u "${USED_PVCS_FILE}" -o "${USED_PVCS_FILE}"

    local found="false"
    local namespace
    local claim_name
    local status
    local storage_class
    local capacity

    while IFS=$'\t' read -r \
        namespace \
        claim_name \
        status \
        storage_class \
        capacity; do

        [[ -z "${namespace}" || -z "${claim_name}" ]] && continue

        if ! grep -Fxq \
            "${namespace}/${claim_name}" \
            "${USED_PVCS_FILE}"; then

            found="true"

            echo "- ${namespace}/${claim_name}" \
                "status=${status}" \
                "storageClass=${storage_class:-NotSet}" \
                "capacity=${capacity:-Unknown}"
        fi

    done < <(
        kubectl get pvc --all-namespaces \
            -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.spec.storageClassName}{"\t"}{.status.capacity.storage}{"\n"}{end}' \
            2>/dev/null
    )

    if [[ "${found}" == "false" ]]; then
        echo "No PVCs without current Pod references detected."
    fi

    echo
    echo "Note: a PVC without a current Pod reference is not automatically orphaned."
    echo "It may belong to a scaled-down workload, stopped application, backup process, or retained StatefulSet."
}

collect_missing_claim_references() {
    local found="false"
    local namespace
    local pod
    local volume_name
    local claim_name

    while IFS=$'\t' read -r namespace pod; do
        [[ -z "${namespace}" || -z "${pod}" ]] && continue

        while IFS=$'\t' read -r volume_name claim_name; do
            [[ -z "${claim_name}" ]] && continue

            if ! kubectl get pvc "${claim_name}" \
                --namespace "${namespace}" \
                >/dev/null 2>&1; then

                found="true"

                echo "- Pod ${namespace}/${pod}" \
                    "references missing PVC ${claim_name}" \
                    "through volume ${volume_name}"
            fi

        done < <(
            kubectl get pod "${pod}" \
                --namespace "${namespace}" \
                -o jsonpath='{range .spec.volumes[?(@.persistentVolumeClaim)]}{.name}{"\t"}{.persistentVolumeClaim.claimName}{"\n"}{end}' \
                2>/dev/null
        )

    done < <(
        kubectl get pods --all-namespaces \
            -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' \
            2>/dev/null
    )

    if [[ "${found}" == "false" ]]; then
        echo "No Pods referencing missing PVCs detected."
    fi
}

main() {
    check_dependency kubectl

    {
        print_separator
        echo "Kubernetes PVC to Workload Mapping"
        print_separator
        echo "Generated: $(date --iso-8601=seconds)"
        echo "Script: ${SCRIPT_NAME}"

        print_section "1. Kubernetes context"

        run_command \
            "current Kubernetes context" \
            kubectl config current-context

        print_section "2. Access validation"

        run_command \
            "Pod access check" \
            kubectl auth can-i list pods --all-namespaces

        run_command \
            "PVC access check" \
            kubectl auth can-i list persistentvolumeclaims --all-namespaces

        run_command \
            "StatefulSet access check" \
            kubectl auth can-i list statefulsets.apps --all-namespaces

        print_section "3. Pod and PVC overview"

        run_command \
            "Pod PVC overview" \
            kubectl get pods --all-namespaces \
                -o custom-columns='NAMESPACE:.metadata.namespace,POD:.metadata.name,PHASE:.status.phase,NODE:.spec.nodeName,PVC-CLAIMS:.spec.volumes[*].persistentVolumeClaim.claimName'

        print_section "4. PVC to Pod and workload mapping"

        collect_pod_pvc_mapping

        print_section "5. StatefulSet volume claim templates"

        collect_statefulset_claim_templates

        print_section "6. PVCs without current Pod references"

        collect_unreferenced_pvcs

        print_section "7. Pods referencing missing PVCs"

        collect_missing_claim_references

        print_section "8. Mapping completion"

        echo "PVC to workload mapping completed."
        echo "Review PVCs without current Pod references before classifying them as unused or orphaned."

    } | tee "${OUTPUT_FILE}"

    echo
    echo "Output saved to:"
    echo "${OUTPUT_FILE}"
}

main "$@"
