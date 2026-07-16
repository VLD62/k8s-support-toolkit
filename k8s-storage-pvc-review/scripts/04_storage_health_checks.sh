#!/usr/bin/env bash

set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"

OUTPUT_DIR="${OUTPUT_DIR:-./outputs}"
OUTPUT_FILE="${OUTPUT_DIR}/04_storage_health_checks_${TIMESTAMP}.txt"

MOUNT_RECORDS_FILE="$(mktemp)"

trap 'rm -f "${MOUNT_RECORDS_FILE}"' EXIT

mkdir -p "${OUTPUT_DIR}"

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

collect_abnormal_storage_resources() {
    local issue_found="false"

    echo "PersistentVolumeClaims not in Bound state:"

    local pvc_output

    pvc_output="$(
        kubectl get pvc --all-namespaces \
            -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,STORAGECLASS:.spec.storageClassName,REQUESTED:.spec.resources.requests.storage,VOLUME:.spec.volumeName' \
            --no-headers 2>/dev/null |
            awk '$3 != "Bound"'
    )"

    if [[ -n "${pvc_output}" ]]; then
        issue_found="true"
        printf '%s\n' "${pvc_output}"
    else
        echo "No abnormal PVC states detected."
    fi

    echo
    echo "PersistentVolumes in abnormal or review-required states:"

    local pv_output

    pv_output="$(
        kubectl get pv \
            -o custom-columns='NAME:.metadata.name,STATUS:.status.phase,CAPACITY:.spec.capacity.storage,STORAGECLASS:.spec.storageClassName,RECLAIM-POLICY:.spec.persistentVolumeReclaimPolicy,CLAIM-NAMESPACE:.spec.claimRef.namespace,CLAIM-NAME:.spec.claimRef.name' \
            --no-headers 2>/dev/null |
            awk '$2 != "Bound"'
    )"

    if [[ -n "${pv_output}" ]]; then
        issue_found="true"
        printf '%s\n' "${pv_output}"
    else
        echo "No abnormal PV states detected."
    fi

    echo
    echo "VolumeAttachments not attached successfully:"

    local attachment_output

    attachment_output="$(
        kubectl get volumeattachments.storage.k8s.io \
            -o custom-columns='NAME:.metadata.name,PV:.spec.source.persistentVolumeName,NODE:.spec.nodeName,ATTACHED:.status.attached,ATTACH-ERROR:.status.attachError.message,DETACH-ERROR:.status.detachError.message' \
            --no-headers 2>/dev/null |
            awk '$4 != "true"'
    )"

    if [[ -n "${attachment_output}" ]]; then
        issue_found="true"
        printf '%s\n' "${attachment_output}"
    else
        echo "No unsuccessful VolumeAttachments detected."
    fi

    echo
    if [[ "${issue_found}" == "false" ]]; then
        echo "[OK] No abnormal PVC, PV, or VolumeAttachment states detected."
    else
        echo "[WARNING] One or more storage resources require review."
    fi
}

collect_storage_events() {
    local events

    events="$(
        kubectl get events --all-namespaces \
            --field-selector type=Warning \
            --sort-by=.metadata.creationTimestamp \
            -o custom-columns='NAMESPACE:.metadata.namespace,LAST-SEEN:.lastTimestamp,REASON:.reason,OBJECT:.involvedObject.kind/.involvedObject.name,MESSAGE:.message' \
            2>/dev/null |
            grep -Ei \
                'volume|persistentvolume|persistentvolumeclaim|attach|detach|mount|unmount|provision|storage|csi|multi-attach|filesystem|resize' |
            tail -n 100 ||
            true
    )"

    if [[ -n "${events}" ]]; then
        printf '%s\n' "${events}"
    else
        echo "No storage-related Warning events detected."
    fi
}

collect_csi_component_health() {
    local csi_pods

    csi_pods="$(
        kubectl get pods \
            --namespace kube-system \
            -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount,NODE:.spec.nodeName' \
            --no-headers 2>/dev/null |
            grep -Ei 'csi|cinder|manila|nfs' ||
            true
    )"

    if [[ -n "${csi_pods}" ]]; then
        printf '%s\n' "${csi_pods}"
    else
        echo "No CSI-related Pods detected in kube-system."
    fi

    echo
    echo "CSI Pods not in Running phase:"

    local unhealthy

    unhealthy="$(
        kubectl get pods \
            --namespace kube-system \
            -o custom-columns='NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount,NODE:.spec.nodeName' \
            --no-headers 2>/dev/null |
            grep -Ei 'csi|cinder|manila|nfs' |
            awk '$2 != "Running"' ||
            true
    )"

    if [[ -n "${unhealthy}" ]]; then
        printf '%s\n' "${unhealthy}"
    else
        echo "No CSI Pods outside Running phase detected."
    fi
}

collect_mount_records() {
    : > "${MOUNT_RECORDS_FILE}"

    local namespace
    local pod
    local phase

    while IFS=$'\t' read -r namespace pod phase; do
        [[ -z "${namespace}" || -z "${pod}" ]] && continue
        [[ "${phase}" != "Running" ]] && continue

        declare -A claim_by_volume=()

        local volume_name
        local claim_name

        while IFS=$'\t' read -r volume_name claim_name; do
            [[ -z "${volume_name}" || -z "${claim_name}" ]] && continue
            claim_by_volume["${volume_name}"]="${claim_name}"
        done < <(
            kubectl get pod "${pod}" \
                --namespace "${namespace}" \
                -o go-template='{{range .spec.volumes}}{{if .persistentVolumeClaim}}{{printf "%s\t%s\n" .name .persistentVolumeClaim.claimName}}{{end}}{{end}}' \
                2>/dev/null
        )

        local container
        local mount_path
        local read_only

        while IFS=$'\t' read -r \
            container \
            volume_name \
            mount_path \
            read_only; do

            [[ -z "${container}" || -z "${volume_name}" ]] && continue

            claim_name="${claim_by_volume[${volume_name}]:-}"

            [[ -z "${claim_name}" ]] && continue

            printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
                "${namespace}" \
                "${pod}" \
                "${container}" \
                "${volume_name}" \
                "${claim_name}" \
                "${mount_path}" \
                "${read_only}" >> "${MOUNT_RECORDS_FILE}"

        done < <(
            kubectl get pod "${pod}" \
                --namespace "${namespace}" \
                -o go-template='{{range .spec.containers}}{{ $container := .name }}{{range .volumeMounts}}{{printf "%s\t%s\t%s\t" $container .name .mountPath}}{{if .readOnly}}true{{else}}false{{end}}{{"\n"}}{{end}}{{end}}' \
                2>/dev/null
        )

        unset claim_by_volume

    done < <(
        kubectl get pods --all-namespaces \
            -o go-template='{{range .items}}{{printf "%s\t%s\t%s\n" .metadata.namespace .metadata.name .status.phase}}{{end}}' \
            2>/dev/null
    )

    sort -u "${MOUNT_RECORDS_FILE}" \
        -o "${MOUNT_RECORDS_FILE}"
}

collect_runtime_filesystem_usage() {
    collect_mount_records

    if [[ ! -s "${MOUNT_RECORDS_FILE}" ]]; then
        echo "No running Pod PVC mounts detected."
        return
    fi

    local namespace
    local pod
    local container
    local volume_name
    local claim_name
    local mount_path
    local read_only

    local checked=0
    local warnings=0
    local critical=0
    local unavailable=0

    while IFS=$'\t' read -r \
        namespace \
        pod \
        container \
        volume_name \
        claim_name \
        mount_path \
        read_only; do

        [[ -z "${namespace}" || -z "${pod}" ]] && continue

        echo
        echo "PVC: ${namespace}/${claim_name}"
        echo "Pod: ${pod}"
        echo "Container: ${container}"
        echo "Volume name: ${volume_name}"
        echo "Mount path: ${mount_path}"
        echo "Read only: ${read_only}"

        local df_output

        if df_output="$(
            kubectl --request-timeout=15s exec \
                --namespace "${namespace}" \
                "${pod}" \
                --container "${container}" \
                -- df -P "${mount_path}" 2>&1
        )"; then
            checked=$((checked + 1))

            printf '%s\n' "${df_output}"

            local usage_percent

            usage_percent="$(
                printf '%s\n' "${df_output}" |
                tail -n 1 |
                awk '{
                    value=$5
                    gsub("%", "", value)

                    if (value ~ /^[0-9]+$/) {
                        print value
                    }
                }'
            )"

            if [[ "${usage_percent}" =~ ^[0-9]+$ ]]; then
                if (( usage_percent >= 90 )); then
                    echo "[CRITICAL] Filesystem utilization is ${usage_percent}%."
                    critical=$((critical + 1))
                elif (( usage_percent >= 80 )); then
                    echo "[WARNING] Filesystem utilization is ${usage_percent}%."
                    warnings=$((warnings + 1))
                else
                    echo "[OK] Filesystem utilization is ${usage_percent}%."
                fi
            else
                echo "[WARNING] Unable to parse filesystem utilization."
            fi
        else
            unavailable=$((unavailable + 1))

            echo "[WARNING] Unable to execute df in this container."
            printf '%s\n' "${df_output}"
        fi

        echo "------------------------------------------------------------"

    done < "${MOUNT_RECORDS_FILE}"

    echo
    echo "Runtime filesystem check summary:"
    echo "  Successful checks: ${checked}"
    echo "  Usage warnings >=80%: ${warnings}"
    echo "  Critical usage >=90%: ${critical}"
    echo "  Unavailable checks: ${unavailable}"

    echo
    echo "A failed df command does not automatically indicate a storage failure."
    echo "The container may not include the df utility or pods/exec access may be restricted."
}

collect_snapshot_inventory() {
    if ! kubectl api-resources \
        --api-group=snapshot.storage.k8s.io \
        --no-headers 2>/dev/null |
        grep -q .; then

        echo "VolumeSnapshot API resources are not available."
        return
    fi

    echo "VolumeSnapshotClasses:"
    kubectl get volumesnapshotclasses.snapshot.storage.k8s.io \
        -o wide 2>&1 ||
        echo "[WARNING] Unable to list VolumeSnapshotClasses."

    echo
    echo "VolumeSnapshots:"
    kubectl get volumesnapshots.snapshot.storage.k8s.io \
        --all-namespaces \
        -o wide 2>&1 ||
        echo "[WARNING] Unable to list VolumeSnapshots."

    echo
    echo "VolumeSnapshotContents:"
    kubectl get volumesnapshotcontents.snapshot.storage.k8s.io \
        -o wide 2>&1 ||
        echo "[WARNING] Unable to list VolumeSnapshotContents."
}

main() {
    check_dependency kubectl

    {
        print_separator
        echo "Kubernetes Storage Health Checks"
        print_separator
        echo "Generated: $(date --iso-8601=seconds)"
        echo "Script: ${SCRIPT_NAME}"

        print_section "1. Kubernetes context"

        run_command \
            "current Kubernetes context" \
            kubectl config current-context

        print_section "2. Access validation"

        run_command \
            "PVC access check" \
            kubectl auth can-i list persistentvolumeclaims --all-namespaces

        run_command \
            "PV access check" \
            kubectl auth can-i list persistentvolumes

        run_command \
            "VolumeAttachment access check" \
            kubectl auth can-i list volumeattachments.storage.k8s.io

        run_command \
            "Pod exec access check" \
            kubectl auth can-i create pods/exec --all-namespaces

        print_section "3. Abnormal PVC, PV, and VolumeAttachment states"

        collect_abnormal_storage_resources

        print_section "4. Storage-related Warning events"

        collect_storage_events

        print_section "5. CSI component health"

        collect_csi_component_health

        print_section "6. Node storage topology"

        run_command \
            "node storage topology" \
            kubectl get nodes \
                -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1].type,STANDARD-ZONE:.metadata.labels.topology\.kubernetes\.io/zone,CINDER-ZONE:.metadata.labels.topology\.cinder\.csi\.openstack\.org/zone,REGION:.metadata.labels.topology\.kubernetes\.io/region'

        print_section "7. Runtime PVC filesystem usage"

        collect_runtime_filesystem_usage

        print_section "8. VolumeSnapshot inventory"

        collect_snapshot_inventory

        print_section "9. Storage policy summary"

        run_command \
            "StorageClass policy summary" \
            kubectl get storageclass \
                -o custom-columns='NAME:.metadata.name,PROVISIONER:.provisioner,RECLAIM-POLICY:.reclaimPolicy,BINDING-MODE:.volumeBindingMode,ALLOW-EXPANSION:.allowVolumeExpansion,DEFAULT:.metadata.annotations.storageclass\.kubernetes\.io/is-default-class'

        print_section "10. Health check completion"

        echo "Storage health checks completed."
        echo "Review warnings before changing StorageClasses, PVCs, or PersistentVolumes."

    } | tee "${OUTPUT_FILE}"

    echo
    echo "Output saved to:"
    echo "${OUTPUT_FILE}"
}

main "$@"
