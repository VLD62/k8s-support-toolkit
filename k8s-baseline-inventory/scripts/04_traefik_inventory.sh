#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-outputs}"
mkdir -p "${OUT_DIR}"

echo "Collecting Traefik ingress controller inventory..."
echo "Output directory: ${OUT_DIR}"

kubectl get all -n traefik -o wide \
  | tee "${OUT_DIR}/16-traefik-all.txt"

kubectl get daemonset -n traefik -o wide \
  | tee "${OUT_DIR}/17-traefik-daemonset.txt"

kubectl get svc -n traefik -o wide \
  | tee "${OUT_DIR}/18-traefik-services.txt"

kubectl get pods -n traefik -o wide --show-labels \
  | tee "${OUT_DIR}/19-traefik-pods-labels.txt"

kubectl describe daemonset traefik -n traefik \
  | tee "${OUT_DIR}/20-traefik-daemonset-describe.txt"

kubectl describe svc traefik -n traefik \
  | tee "${OUT_DIR}/21-traefik-service-describe.txt"

echo
echo "Done. Traefik inventory collected in: ${OUT_DIR}"
