#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-outputs}"
mkdir -p "${OUT_DIR}"

echo "Collecting Kubernetes node inventory..."
echo "Output directory: ${OUT_DIR}"

kubectl get nodes -o wide | tee "${OUT_DIR}/06-nodes-wide.txt"

kubectl get nodes \
  -L kubernetes.io/role,node-role.kubernetes.io/control-plane,node-role.kubernetes.io/worker \
  | tee "${OUT_DIR}/07-nodes-roles.txt"

kubectl get nodes -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1].type,ROLES:.metadata.labels.node-role\.kubernetes\.io/worker,VERSION:.status.nodeInfo.kubeletVersion,OS:.status.nodeInfo.osImage,KERNEL:.status.nodeInfo.kernelVersion,CONTAINER-RUNTIME:.status.nodeInfo.containerRuntimeVersion' \
  | tee "${OUT_DIR}/08-nodes-summary.txt"

kubectl describe nodes | tee "${OUT_DIR}/09-nodes-describe.txt"

echo
echo "Done. Node inventory collected in: ${OUT_DIR}"
