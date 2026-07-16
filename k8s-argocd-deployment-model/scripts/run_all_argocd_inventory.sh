#!/usr/bin/env bash

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLSET_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
OUTPUT_DIR="${OUTPUT_DIR:-${TOOLSET_DIR}/output}"
EXECUTION_LOG="${OUTPUT_DIR}/00_argocd_inventory_execution_${TIMESTAMP}.log"

mkdir -p "${OUTPUT_DIR}"

exec > >(tee "${EXECUTION_LOG}") 2>&1

SCRIPTS=(
    "01_argocd_environment_inventory.sh"
    "02_argocd_applications_projects_inventory.sh"
    "03_argocd_sync_health_diagnostics.sh"
    "04_argocd_operational_configuration_inventory.sh"
)

echo "======================================================================"
echo "Argo CD Inventory Bundle"
echo "======================================================================"
echo "Started at: $(date --iso-8601=seconds)"
echo "Kubernetes context: $(kubectl config current-context 2>/dev/null || true)"
echo "Argo CD namespace: ${ARGOCD_NAMESPACE:-argocd}"
echo "Output directory: ${OUTPUT_DIR}"
echo

successful_scripts=0
failed_scripts=0

for script in "${SCRIPTS[@]}"; do
    script_path="${SCRIPT_DIR}/${script}"

    echo "----------------------------------------------------------------------"
    echo "Running: ${script}"
    echo "----------------------------------------------------------------------"

    if [[ ! -f "${script_path}" ]]; then
        echo "[ERROR] Script not found: ${script_path}"
        failed_scripts=$((failed_scripts + 1))
        echo
        continue
    fi

    if [[ ! -x "${script_path}" ]]; then
        echo "[WARNING] Script is not executable: ${script_path}"
        echo "[WARNING] Running it through Bash."
    fi

    if OUTPUT_DIR="${OUTPUT_DIR}" \
       ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}" \
       bash "${script_path}"; then
        echo
        echo "[SUCCESS] ${script}"
        successful_scripts=$((successful_scripts + 1))
    else
        exit_code=$?

        echo
        echo "[FAILED] ${script}"
        echo "[FAILED] Exit code: ${exit_code}"

        failed_scripts=$((failed_scripts + 1))
    fi

    echo
done

echo "======================================================================"
echo "Execution Summary"
echo "======================================================================"
echo "Finished at: $(date --iso-8601=seconds)"
echo "Successful scripts: ${successful_scripts}"
echo "Failed scripts: ${failed_scripts}"
echo "Execution log: ${EXECUTION_LOG}"

if [[ "${failed_scripts}" -gt 0 ]]; then
    exit 1
fi
