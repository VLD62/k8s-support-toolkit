#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLSET_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${1:-${TOOLSET_DIR}/outputs}"

mkdir -p "${OUT_DIR}"

scripts=(
    "01_context_access_inventory.sh"
    "02_nodes_inventory.sh"
    "03_namespaces_workloads_inventory.sh"
    "04_traefik_inventory.sh"
    "05_argocd_inventory.sh"
    "06_storage_inventory.sh"
    "07_ingress_service_inventory.sh"
)

for script in "${scripts[@]}"; do
    "${SCRIPT_DIR}/${script}" "${OUT_DIR}"
done

echo
echo "Baseline inventory collection completed."
echo "Output directory: ${OUT_DIR}"
