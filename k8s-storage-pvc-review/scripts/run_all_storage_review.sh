#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

TOOLSET_DIR="$(
    cd "${SCRIPT_DIR}/.." &&
    pwd
)"

TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"

OUTPUT_DIR="${OUTPUT_DIR:-${TOOLSET_DIR}/outputs}"
EXECUTION_LOG="${OUTPUT_DIR}/00_storage_review_execution_${TIMESTAMP}.log"
STATUS_FILE="${OUTPUT_DIR}/00_storage_review_status_${TIMESTAMP}.md"

mkdir -p "${OUTPUT_DIR}"

SCRIPTS=(
    "01_storage_classes_inventory.sh"
    "02_pv_pvc_inventory.sh"
    "03_pvc_workload_mapping.sh"
    "04_storage_health_checks.sh"
)

success_count=0
failure_count=0

{
    echo "Kubernetes storage review"
    echo "Generated: $(date --iso-8601=seconds)"
    echo "Output directory: ${OUTPUT_DIR}"
    echo

    for script in "${SCRIPTS[@]}"; do
        script_path="${SCRIPT_DIR}/${script}"

        echo "================================================================"
        echo "Running: ${script}"
        echo "================================================================"

        if [[ ! -x "${script_path}" ]]; then
            echo "[ERROR] Script is missing or not executable: ${script_path}"
            failure_count=$((failure_count + 1))
            echo
            continue
        fi

        if OUTPUT_DIR="${OUTPUT_DIR}" "${script_path}"; then
            echo
            echo "[OK] ${script}"
            success_count=$((success_count + 1))
        else
            exit_code=$?

            echo
            echo "[ERROR] ${script} exited with code ${exit_code}"
            failure_count=$((failure_count + 1))
        fi

        echo
    done

    echo "================================================================"
    echo "Execution summary"
    echo "================================================================"
    echo "Successful scripts: ${success_count}"
    echo "Failed scripts: ${failure_count}"

} 2>&1 | tee "${EXECUTION_LOG}"

{
    echo "# Kubernetes Storage Review Status"
    echo
    echo "- Generated: $(date --iso-8601=seconds)"
    echo "- Successful scripts: ${success_count}"
    echo "- Failed scripts: ${failure_count}"
    echo "- Execution log: $(basename "${EXECUTION_LOG}")"
    echo

    if [[ "${failure_count}" -eq 0 ]]; then
        echo "## Result"
        echo
        echo "All storage review scripts completed successfully."
    else
        echo "## Result"
        echo
        echo "One or more storage review scripts failed. Review the execution log."
    fi
} > "${STATUS_FILE}"

echo
echo "Execution log:"
echo "${EXECUTION_LOG}"
echo
echo "Status file:"
echo "${STATUS_FILE}"

if [[ "${failure_count}" -gt 0 ]]; then
    exit 1
fi
