#!/usr/bin/env bash

set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"

OUTPUT_DIR="${OUTPUT_DIR:-./outputs}"
OUTPUT_FILE="${OUTPUT_DIR}/01_storage_classes_inventory_${TIMESTAMP}.txt"

mkdir -p "${OUTPUT_DIR}"

print_separator() {
    printf '%*s\n' 100 '' | tr ' ' '='
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

collect_default_storage_classes() {
    {
        kubectl get storageclass \
            -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' \
            2>/dev/null

        kubectl get storageclass \
            -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.beta\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' \
            2>/dev/null
    } | sed '/^[[:space:]]*$/d' | sort -u
}

collect_storage_class_details() {
    local storage_class

    while IFS= read -r storage_class; do
        [[ -z "${storage_class}" ]] && continue

        echo
        echo "StorageClass: ${storage_class}"
        echo "----------------------------------------"

        kubectl get storageclass "${storage_class}" \
            -o jsonpath='
Provisioner: {.provisioner}
Reclaim policy: {.reclaimPolicy}
Volume binding mode: {.volumeBindingMode}
Allow volume expansion: {.allowVolumeExpansion}
Mount options: {.mountOptions}
Allowed topologies: {.allowedTopologies}
Parameters: {.parameters}
Created: {.metadata.creationTimestamp}
' 2>&1 || echo "[WARNING] Unable to read StorageClass ${storage_class}"

    done < <(
        kubectl get storageclass \
            -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
            2>/dev/null
    )
}

collect_validation_summary() {
    local storage_class_count
    local default_storage_classes
    local default_count

    storage_class_count="$(
        kubectl get storageclass \
            --no-headers 2>/dev/null |
            wc -l |
            tr -d ' '
    )"

    default_storage_classes="$(collect_default_storage_classes)"
    default_count="$(
        printf '%s\n' "${default_storage_classes}" |
        sed '/^[[:space:]]*$/d' |
        wc -l |
        tr -d ' '
    )"

    echo "StorageClasses found: ${storage_class_count}"
    echo "Default StorageClasses found: ${default_count}"

    if [[ "${default_count}" -eq 0 ]]; then
        echo "[WARNING] No default StorageClass is configured."
    elif [[ "${default_count}" -gt 1 ]]; then
        echo "[WARNING] Multiple default StorageClasses are configured:"
        printf '%s\n' "${default_storage_classes}"
    else
        echo "[OK] Default StorageClass:"
        printf '%s\n' "${default_storage_classes}"
    fi

    echo
    echo "StorageClasses using Immediate binding:"

    kubectl get storageclass \
        -o jsonpath='{range .items[?(@.volumeBindingMode=="Immediate")]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null |
        sed '/^[[:space:]]*$/d' |
        sed 's/^/- /'

    echo
    echo "StorageClasses without volume expansion enabled:"

    kubectl get storageclass \
        -o jsonpath='{range .items[?(@.allowVolumeExpansion!=true)]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null |
        sed '/^[[:space:]]*$/d' |
        sed 's/^/- /'

    echo
    echo "StorageClasses using Retain reclaim policy:"

    kubectl get storageclass \
        -o jsonpath='{range .items[?(@.reclaimPolicy=="Retain")]}{.metadata.name}{"\n"}{end}' \
        2>/dev/null |
        sed '/^[[:space:]]*$/d' |
        sed 's/^/- /'
}

main() {
    check_dependency kubectl

    {
        print_separator
        echo "Kubernetes StorageClass Inventory"
        print_separator
        echo "Generated: $(date --iso-8601=seconds)"
        echo "Script: ${SCRIPT_NAME}"

        print_section "1. Kubernetes context"

        run_command \
            "current Kubernetes context" \
            kubectl config current-context

        print_section "2. Access validation"

        run_command \
            "StorageClass access check" \
            kubectl auth can-i list storageclasses.storage.k8s.io

        run_command \
            "CSIDriver access check" \
            kubectl auth can-i list csidrivers.storage.k8s.io

        print_section "3. StorageClass overview"

        run_command \
            "StorageClass overview" \
            kubectl get storageclass -o wide

        print_section "4. StorageClass structured inventory"

        run_command \
            "StorageClass structured inventory" \
            kubectl get storageclass \
                -o custom-columns='NAME:.metadata.name,PROVISIONER:.provisioner,RECLAIM-POLICY:.reclaimPolicy,BINDING-MODE:.volumeBindingMode,ALLOW-EXPANSION:.allowVolumeExpansion,DEFAULT:.metadata.annotations.storageclass\.kubernetes\.io/is-default-class'

        print_section "5. StorageClass detailed configuration"

        collect_storage_class_details

        print_section "6. Default StorageClass configuration"

        default_storage_classes="$(collect_default_storage_classes)"

        if [[ -n "${default_storage_classes}" ]]; then
            printf '%s\n' "${default_storage_classes}"
        else
            echo "No default StorageClass detected."
        fi

        print_section "7. CSI drivers"

        run_command \
            "CSI driver inventory" \
            kubectl get csidriver -o wide

        print_section "8. StorageClass validation summary"

        collect_validation_summary

        print_section "9. Inventory completion"

        echo "StorageClass inventory completed."
        echo "Review warnings manually before making configuration changes."

    } | tee "${OUTPUT_FILE}"

    echo
    echo "Output saved to:"
    echo "${OUTPUT_FILE}"
}

main "$@"
