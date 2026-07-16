#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-outputs}"
mkdir -p "${OUT_DIR}"

echo "Collecting Argo CD inventory..."
echo "Output directory: ${OUT_DIR}"

kubectl get all -n argocd -o wide \
  | tee "${OUT_DIR}/22-argocd-all.txt"

kubectl get deploy,statefulset,svc -n argocd -o wide \
  | tee "${OUT_DIR}/23-argocd-main-resources.txt"

kubectl get pods -n argocd -o wide --show-labels \
  | tee "${OUT_DIR}/24-argocd-pods-labels.txt"

kubectl get ingress -n argocd -o wide \
  | tee "${OUT_DIR}/25-argocd-ingress.txt"

kubectl get configmap -n argocd \
  | tee "${OUT_DIR}/26-argocd-configmaps.txt"

echo
echo "Done. Argo CD inventory collected in: ${OUT_DIR}"
