#!/usr/bin/env bash

set -u

OUTPUT_DIR="outputs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_FILE="${OUTPUT_DIR}/02_ingress_inventory_${TIMESTAMP}.txt"
SUMMARY_FILE="${OUTPUT_DIR}/02_ingress_summary_${TIMESTAMP}.csv"

mkdir -p "${OUTPUT_DIR}"

{
  echo "============================================================"
  echo "Kubernetes Ingress Inventory"
  echo "Generated at: $(date)"
  echo "Kubernetes context: $(kubectl config current-context 2>/dev/null || echo 'N/A')"
  echo "============================================================"
  echo

  echo "## 1. Ingress resources overview"
  kubectl get ingress -A -o wide 2>/dev/null || true
  echo

  echo "## 2. Ingress resources with class"
  kubectl get ingress -A \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.ingressClassName,HOSTS:.spec.rules[*].host,ADDRESS:.status.loadBalancer.ingress[*].ip,PORTS:.spec.rules[*].http.paths[*].backend.service.port.number,AGE:.metadata.creationTimestamp' \
    2>/dev/null || true
  echo

  echo "## 3. IngressClass resources"
  kubectl get ingressclass -o wide 2>/dev/null || true
  echo

  echo "## 4. Detailed Ingress description"
  kubectl describe ingress -A 2>/dev/null || true
  echo

  echo "## 5. Ingress YAML export"
  kubectl get ingress -A -o yaml 2>/dev/null || true
  echo

  echo "## 6. Ingress resources using Traefik class"
  kubectl get ingress -A \
    -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.ingressClassName,HOSTS:.spec.rules[*].host' \
    2>/dev/null | grep -i traefik || true
  echo

  echo "## 7. Ingress annotations overview"
  for ns in $(kubectl get ingress -A --no-headers 2>/dev/null | awk '{print $1}' | sort -u); do
    for ing in $(kubectl get ingress -n "${ns}" --no-headers 2>/dev/null | awk '{print $1}'); do
      echo "### ${ns}/${ing}"
      kubectl get ingress -n "${ns}" "${ing}" -o jsonpath='{.metadata.annotations}' 2>/dev/null || true
      echo
      echo
    done
  done

  echo "============================================================"
  echo "End of Kubernetes Ingress inventory"
  echo "============================================================"

} | tee "${OUTPUT_FILE}"

echo "namespace,ingress,ingress_class,host,path,service,service_port,tls" > "${SUMMARY_FILE}"

for ns in $(kubectl get ingress -A --no-headers 2>/dev/null | awk '{print $1}' | sort -u); do
  for ing in $(kubectl get ingress -n "${ns}" --no-headers 2>/dev/null | awk '{print $1}'); do

    ingress_class="$(kubectl get ingress -n "${ns}" "${ing}" -o jsonpath='{.spec.ingressClassName}' 2>/dev/null)"
    tls_hosts="$(kubectl get ingress -n "${ns}" "${ing}" -o jsonpath='{.spec.tls[*].hosts[*]}' 2>/dev/null)"

    kubectl get ingress -n "${ns}" "${ing}" -o jsonpath='{range .spec.rules[*]}{.host}{"|"}{range .http.paths[*]}{.path}{"|"}{.backend.service.name}{"|"}{.backend.service.port.number}{"\n"}{end}{end}' 2>/dev/null | while IFS='|' read -r host path service service_port; do

      if echo "${tls_hosts}" | grep -q "${host}"; then
        tls="yes"
      else
        tls="no"
      fi

      echo "${ns},${ing},${ingress_class},${host},${path},${service},${service_port},${tls}" >> "${SUMMARY_FILE}"

    done
  done
done

echo
echo "Inventory saved to: ${OUTPUT_FILE}"
echo "Summary CSV saved to: ${SUMMARY_FILE}"
