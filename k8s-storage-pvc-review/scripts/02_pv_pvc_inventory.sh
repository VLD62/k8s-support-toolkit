#!/usr/bin/env bash

set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"

OUTPUT_DIR="${OUTPUT_DIR:-./outputs}"
OUTPUT_FILE="${OUTPUT_DIR}/02_pv_pvc_inventory_${TIMESTAMP}.txt"

mkdir -p "${OUTPUT_DIR}"

print_separator() {
    printf '%*s\n' 110 '' | tr ' ' '='
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

count_pvs() {
    kubectl get pv --no-headers 2>/dev/null |
        sed '/^[[:space:]]*$/d' |
        wc -l |
        tr -d ' '
}

count_pv_status() {
    local status="$1"

    kubectl get pv --no-headers 2>/dev/null |
        awk -v expected="${status}" '$5 == expected {count++} END {print count+0}'
}

count_pv_storage_class() {
    local storage_class="$1"

    kubectl get pv \
        -o custom-columns='STORAGECLASS:.spec.storageClassName' \
        --no-headers 2>/dev/null |
        awk -v expected="${storage_class}" '$1 == expected {count++} END {print count+0}'
}

count_pvcs() {
    kubectl get pvc --all-namespaces --no-headers 2>/dev/null |
        sed '/^[[:space:]]*$/d' |
        wc -l |
        tr -d ' '
}

count_pvc_status() {
    local status="$1"

    kubectl get pvc --all-namespaces --no-headers 2>/dev/null |
        awk -v expected="${status}" '$3 == expected {count++} END {print count+0}'
}

collect_pv_details() {
    local pv

    while IFS= read -r pv; do
        [[ -z "${pv}" ]] && continue

        echo
        echo "PersistentVolume: ${pv}"
        echo "------------------------------------------------------------"

        kubectl get pv "${pv}" \
            -o jsonpath='
Status: {.status.phase}
Capacity: {.spec.capacity.storage}
Access modes: {.spec.accessModes}
Volume mode: {.spec.volumeMode}
StorageClass: {.spec.storageClassName}
Reclaim policy: {.spec.persistentVolumeReclaimPolicy}
Claim: {.spec.claimRef.namespace}/{.spec.claimRef.name}
CSI driver: {.spec.csi.driver}
Volume handle: {.spec.csi.volumeHandle}
Filesystem type: {.spec.csi.fsType}
Mount options: {.spec.mountOptions}
Node affinity: {.spec.nodeAffinity}
Created: {.metadata.creationTimestamp}
' 2>&1 || echo "[WARNING] Unable to read PersistentVolume ${pv}"

    done < <(
        kubectl get pv \
            -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
            2>/dev/null
    )
}

collect_pvc_details() {
    local namespace
    local pvc

    while IFS=$'\t' read -r namespace pvc; do
        [[ -z "${namespace}" || -z "${pvc}" ]] && continue

        echo
        echo "PersistentVolumeClaim: ${namespace}/${pvc}"
        echo "------------------------------------------------------------"

        kubectl get pvc "${pvc}" \
            --namespace "${namespace}" \
            -o jsonpath='
Status: {.status.phase}
Bound volume: {.spec.volumeName}
StorageClass: {.spec.storageClassName}
Requested capacity: {.spec.resources.requests.storage}
Actual capacity: {.status.capacity.storage}
Access modes requested: {.spec.accessModes}
Access modes assigned: {.status.accessModes}
Volume mode: {.spec.volumeMode}
Selector: {.spec.selector}
Data source: {.spec.dataSource}
Created: {.metadata.creationTimestamp}
' 2>&1 || echo "[WARNING] Unable to read PVC ${namespace}/${pvc}"

    done < <(
        kubectl get pvc --all-namespaces \
            -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' \
            2>/dev/null
    )
}

collect_storage_class_usage() {
    local storage_class

    while IFS= read -r storage_class; do
        [[ -z "${storage_class}" ]] && continue

        local pv_count
        local pvc_count

        pv_count="$(count_pv_storage_class "${storage_class}")"

        pvc_count="$(
            kubectl get pvc --all-namespaces \
                -o custom-columns='STORAGECLASS:.spec.storageClassName' \
                --no-headers 2>/dev/null |
                awk -v expected="${storage_class}" \
                    '$1 == expected {count++} END {print count+0}'
        )"

        echo "${storage_class}:"
        echo "  PersistentVolumes: ${pv_count}"
        echo "  PersistentVolumeClaims: ${pvc_count}"

    done < <(
        kubectl get storageclass \
            -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
            2>/dev/null
    )
}

collect_validation_summary() {
    local total_pvs
    local total_pvcs

    total_pvs="$(count_pvs)"
    total_pvcs="$(count_pvcs)"

    echo "PersistentVolumes found: ${total_pvs}"
    echo "PersistentVolumeClaims found: ${total_pvcs}"

    echo
    echo "PersistentVolume status summary:"
    echo "  Bound:     $(count_pv_status Bound)"
    echo "  Available: $(count_pv_status Available)"
    echo "  Released:  $(count_pv_status Released)"
    echo "  Failed:    $(count_pv_status Failed)"
    echo "  Pending:   $(count_pv_status Pending)"

    echo
    echo "PersistentVolumeClaim status summary:"
    echo "  Bound:   $(count_pvc_status Bound)"
    echo "  Pending: $(count_pvc_status Pending)"
    echo "  Lost:    $(count_pvc_status Lost)"

    echo
    echo "PVCs without an explicit StorageClass:"

    kubectl get pvc --all-namespaces \
        -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,STORAGECLASS:.spec.storageClassName' \
        --no-headers 2>/dev/null |
        awk '$4 == "<none>" || $4 == "" {print "- " $1 "/" $2 " [" $3 "]"}'

    echo
    echo "Pending PVCs:"

    kubectl get pvc --all-namespaces \
        -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STORAGECLASS:.spec.storageClassName,REQUESTED:.spec.resources.requests.storage,STATUS:.status.phase' \
        --no-headers 2>/dev/null |
        awk '$5 == "Pending" {
            print "- " $1 "/" $2 \
            " storageClass=" $3 \
            " requested=" $4
        }'

    echo
    echo "Lost PVCs:"

    kubectl get pvc --all-namespaces \
        -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,VOLUME:.spec.volumeName,STATUS:.status.phase' \
        --no-headers 2>/dev/null |
        awk '$4 == "Lost" {
            print "- " $1 "/" $2 \
            " volume=" $3
        }'

    echo
    echo "Released or failed PersistentVolumes:"

    kubectl get pv \
        -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.namespace/.spec.claimRef.name,STORAGECLASS:.spec.storageClassName,CAPACITY:.spec.capacity.storage' \
        --no-headers 2>/dev/null |
        awk '$2 == "Released" || $2 == "Failed" {
            print "- " $1 \
            " status=" $2 \
            " claim=" $3 \
            " storageClass=" $4 \
            " capacity=" $5
        }'
}

main() {
    check_dependency kubectl

    {
        print_separator
        echo "Kubernetes PersistentVolume and PersistentVolumeClaim Inventory"
        print_separator
        echo "Generated: $(date --iso-8601=seconds)"
        echo "Script: ${SCRIPT_NAME}"

        print_section "1. Kubernetes context"

        run_command \
            "current Kubernetes context" \
            kubectl config current-context

        print_section "2. Access validation"

        run_command \
            "PersistentVolume access check" \
            kubectl auth can-i list persistentvolumes

        run_command \
            "PersistentVolumeClaim access check" \
            kubectl auth can-i list persistentvolumeclaims --all-namespaces

        run_command \
            "VolumeAttachment access check" \
            kubectl auth can-i list volumeattachments.storage.k8s.io

        print_section "3. PersistentVolume overview"

        run_command \
            "PersistentVolume overview" \
            kubectl get persistentvolumes -o wide

        print_section "4. PersistentVolumeClaim overview"

        run_command \
            "PersistentVolumeClaim overview" \
            kubectl get persistentvolumeclaims --all-namespaces -o wide

        print_section "5. PersistentVolumes grouped by StorageClass"

        run_command \
            "PersistentVolumes grouped by StorageClass" \
            kubectl get pv \
                --sort-by=.spec.storageClassName \
                -o custom-columns='NAME:.metadata.name,CAPACITY:.spec.capacity.storage,ACCESS-MODES:.spec.accessModes,RECLAIM-POLICY:.spec.persistentVolumeReclaimPolicy,STATUS:.status.phase,CLAIM:.spec.claimRef.namespace/.spec.claimRef.name,STORAGECLASS:.spec.storageClassName,AGE:.metadata.creationTimestamp'

        print_section "6. PersistentVolumeClaims grouped by namespace"

        run_command \
            "PersistentVolumeClaims grouped by namespace" \
            kubectl get pvc --all-namespaces \
                --sort-by=.metadata.namespace \
                -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName,CAPACITY:.status.capacity.storage,REQUESTED:.spec.resources.requests.storage,ACCESS-MODES:.spec.accessModes,STORAGECLASS:.spec.storageClassName,AGE:.metadata.creationTimestamp'

        print_section "7. StorageClass usage summary"

        collect_storage_class_usage

        print_section "8. Detailed PersistentVolume configuration"

        collect_pv_details

        print_section "9. Detailed PersistentVolumeClaim configuration"

        collect_pvc_details

        print_section "10. VolumeAttachments"

        run_command \
            "VolumeAttachment inventory" \
            kubectl get volumeattachments.storage.k8s.io -o wide

        print_section "11. Validation summary"

        collect_validation_summary

        print_section "12. Inventory completion"

        echo "PersistentVolume and PersistentVolumeClaim inventory completed."
        echo "Review warnings and abnormal resource states manually."

    } | tee "${OUTPUT_FILE}"

    echo
    echo "Output saved to:"
    echo "${OUTPUT_FILE}"
}

main "$@"
