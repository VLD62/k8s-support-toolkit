#!/usr/bin/env bash

set -u

OUTPUT_DIR="outputs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_FILE="${OUTPUT_DIR}/01_traefik_inventory_${TIMESTAMP}.txt"

mkdir -p "${OUTPUT_DIR}"

{
  echo "============================================================"
  echo "Traefik Ingress Controller Inventory"
  echo "Generated at: $(date)"
  echo "Kubernetes context: $(kubectl config current-context 2>/dev/null || echo 'N/A')"
  echo "============================================================"
  echo

  echo "## 1. Traefik related namespaces"
  kubectl get namespaces | grep -i traefik || true
  echo

  echo "## 2. Traefik pods"
  kubectl get pods -A -o wide | grep -i traefik || true
  echo

  echo "## 3. Traefik deployments"
  kubectl get deployments -A -o wide | grep -i traefik || true
  echo

  echo "## 4. Traefik daemonsets"
  kubectl get daemonsets -A -o wide | grep -i traefik || true
  echo

  echo "## 5. Traefik services"
  kubectl get services -A -o wide | grep -i traefik || true
  echo

  echo "## 6. Traefik configmaps"
  kubectl get configmaps -A | grep -i traefik || true
  echo

  echo "## 7. Traefik secrets"
  kubectl get secrets -A | grep -i traefik || true
  echo

  echo "## 8. IngressClasses"
  kubectl get ingressclass -o wide 2>/dev/null || true
  echo

  echo "## 9. Traefik CRDs"
  kubectl get crd | grep -i traefik || true
  echo

  echo "## 10. Traefik IngressRoutes, if available"
  kubectl get ingressroute -A -o wide 2>/dev/null || true
  echo

  echo "## 11. Traefik Middlewares, if available"
  kubectl get middleware -A -o wide 2>/dev/null || true
  echo

  echo "## 12. Traefik TLSStores, if available"
  kubectl get tlsstore -A 2>/dev/null || true
  echo

  echo "## 13. Traefik TLSOptions, if available"
  kubectl get tlsoption -A 2>/dev/null || true
  echo

  echo "## 14. Traefik related events"
  kubectl get events -A --sort-by=.lastTimestamp | grep -i traefik | tail -50 || true
  echo

  echo "============================================================"
  echo "End of Traefik inventory"
  echo "============================================================"

} | tee "${OUTPUT_FILE}"

echo
echo "Inventory saved to: ${OUTPUT_FILE}"
