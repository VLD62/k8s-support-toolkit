#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-outputs}"
mkdir -p "${OUT_DIR}"

echo "Collecting Kubernetes ingress and service exposure inventory..."
echo "Output directory: ${OUT_DIR}"

kubectl get ingressclass -o wide \
  | tee "${OUT_DIR}/31-ingressclasses.txt"

kubectl get ingress -A -o wide \
  | tee "${OUT_DIR}/32-ingresses-wide.txt"

kubectl describe ingress -A \
  | tee "${OUT_DIR}/33-ingresses-describe.txt"

kubectl get svc -A -o wide \
  | tee "${OUT_DIR}/34-services-wide.txt"

kubectl get svc -A --field-selector spec.type=LoadBalancer -o wide \
  | tee "${OUT_DIR}/35-loadbalancer-services.txt"

kubectl get svc -A --field-selector spec.type=NodePort -o wide \
  | tee "${OUT_DIR}/36-nodeport-services.txt"

kubectl get endpoints -A \
  | tee "${OUT_DIR}/37-endpoints.txt"

kubectl get endpointslices -A \
  | tee "${OUT_DIR}/38-endpointslices.txt"

echo
echo "Done. Ingress and service exposure inventory collected in: ${OUT_DIR}"
