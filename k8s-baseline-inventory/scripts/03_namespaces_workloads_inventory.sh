#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-outputs}"
mkdir -p "${OUT_DIR}"

echo "Collecting Kubernetes namespaces and workload inventory..."
echo "Output directory: ${OUT_DIR}"

kubectl get namespaces \
  | tee "${OUT_DIR}/10-namespaces.txt"

kubectl get namespaces --show-labels \
  | tee "${OUT_DIR}/15-namespaces-labels.txt"

kubectl get pods -A -o wide \
  | tee "${OUT_DIR}/11-pods-wide.txt"

kubectl get deploy,statefulset,daemonset -A \
  | tee "${OUT_DIR}/12-workload-controllers.txt"

kubectl get svc -A \
  | tee "${OUT_DIR}/13-services.txt"

kubectl get pods -A --no-headers \
  | awk '{count[$1]++} END {for (ns in count) print ns, count[ns]}' \
  | sort \
  | tee "${OUT_DIR}/14-pod-counts-by-namespace.txt"

echo
echo "Done. Namespace and workload inventory collected in: ${OUT_DIR}"
