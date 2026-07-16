#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-outputs}"
mkdir -p "${OUT_DIR}"

echo "Collecting Kubernetes storage inventory..."
echo "Output directory: ${OUT_DIR}"

kubectl get storageclass -o wide \
  | tee "${OUT_DIR}/27-storageclasses.txt"

kubectl describe storageclass \
  | tee "${OUT_DIR}/28-storageclasses-describe.txt"

kubectl get pvc -A -o wide \
  | tee "${OUT_DIR}/29-pvcs-wide.txt"

kubectl get pv -o wide \
  | tee "${OUT_DIR}/30-pvs-wide.txt"

echo
echo "Done. Storage inventory collected in: ${OUT_DIR}"
