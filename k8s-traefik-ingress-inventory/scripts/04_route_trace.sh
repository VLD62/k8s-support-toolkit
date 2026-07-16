#!/usr/bin/env bash

set -u

OUTPUT_DIR="outputs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

NAMESPACE="${1:-}"
INGRESS_NAME="${2:-}"

if [[ -z "${NAMESPACE}" || -z "${INGRESS_NAME}" ]]; then
  echo "Usage: 04_route_trace.sh <namespace> <ingress-name>" >&2
  echo "Example: 04_route_trace.sh example-app example-ingress" >&2
  exit 1
fi

OUTPUT_FILE="${OUTPUT_DIR}/04_route_trace_${NAMESPACE}_${INGRESS_NAME}_${TIMESTAMP}.txt"

mkdir -p "${OUTPUT_DIR}"

print_section() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
  echo
}

get_service_selector() {
  local ns="$1"
  local svc="$2"

  kubectl get service -n "${ns}" "${svc}" \
    -o jsonpath='{range $k,$v := .spec.selector}{printf "%s=%s," $k $v}{end}' 2>/dev/null \
    | sed 's/,$//'
}

{
  echo "============================================================"
  echo "Kubernetes Ingress Route Trace"
  echo "Generated at: $(date)"
  echo "Kubernetes context: $(kubectl config current-context 2>/dev/null || echo 'N/A')"
  echo "Namespace: ${NAMESPACE}"
  echo "Ingress: ${INGRESS_NAME}"
  echo "============================================================"

  print_section "1. Ingress overview"
  kubectl get ingress -n "${NAMESPACE}" "${INGRESS_NAME}" -o wide 2>/dev/null || {
    echo "Ingress ${NAMESPACE}/${INGRESS_NAME} not found."
    exit 1
  }

  print_section "2. Ingress details"
  kubectl describe ingress -n "${NAMESPACE}" "${INGRESS_NAME}" 2>/dev/null || true

  print_section "3. Ingress YAML"
  kubectl get ingress -n "${NAMESPACE}" "${INGRESS_NAME}" -o yaml 2>/dev/null || true

  print_section "4. Route backend mapping"

  kubectl get ingress -n "${NAMESPACE}" "${INGRESS_NAME}" \
    -o jsonpath='{range .spec.rules[*]}{.host}{"|"}{range .http.paths[*]}{.path}{"|"}{.pathType}{"|"}{.backend.service.name}{"|"}{.backend.service.port.name}{.backend.service.port.number}{"\n"}{end}{end}' \
    2>/dev/null | while IFS='|' read -r host path path_type service service_port; do

      echo "Host: ${host}"
      echo "Path: ${path}"
      echo "Path type: ${path_type}"
      echo "Backend Service: ${NAMESPACE}/${service}"
      echo "Backend Service Port: ${service_port}"
      echo

      print_section "5. Backend Service: ${NAMESPACE}/${service}"
      kubectl get service -n "${NAMESPACE}" "${service}" -o wide 2>/dev/null || true
      echo
      kubectl describe service -n "${NAMESPACE}" "${service}" 2>/dev/null || true

      print_section "6. Endpoints for Service: ${NAMESPACE}/${service}"
      kubectl get endpoints -n "${NAMESPACE}" "${service}" -o wide 2>/dev/null || true
      echo
      kubectl get endpoints -n "${NAMESPACE}" "${service}" -o yaml 2>/dev/null || true

      print_section "7. EndpointSlices for Service: ${NAMESPACE}/${service}"
      kubectl get endpointslices -n "${NAMESPACE}" \
        -l kubernetes.io/service-name="${service}" \
        -o wide 2>/dev/null || true
      echo
      kubectl get endpointslices -n "${NAMESPACE}" \
        -l kubernetes.io/service-name="${service}" \
        -o yaml 2>/dev/null || true

      print_section "8. Backend Pods selected by Service: ${NAMESPACE}/${service}"

      selector="$(get_service_selector "${NAMESPACE}" "${service}")"

      echo "Service selector: ${selector}"
      echo

      if [ -n "${selector}" ] && [ "${selector}" != "<none>" ]; then
        kubectl get pods -n "${NAMESPACE}" -l "${selector}" -o wide 2>/dev/null || true
        echo

        echo "### Pod details"
        for pod in $(kubectl get pods -n "${NAMESPACE}" -l "${selector}" --no-headers 2>/dev/null | awk '{print $1}'); do
          echo
          echo "------------------------------------------------------------"
          echo "Pod: ${NAMESPACE}/${pod}"
          echo "------------------------------------------------------------"
          kubectl describe pod -n "${NAMESPACE}" "${pod}" 2>/dev/null || true
        done
      else
        echo "No selector found for Service ${NAMESPACE}/${service}."
      fi

      print_section "9. Route summary"

      echo "External route:"
      echo "  https://${host}${path}"
      echo
      echo "Kubernetes route:"
      echo "  Ingress:  ${NAMESPACE}/${INGRESS_NAME}"
      echo "  Service:  ${NAMESPACE}/${service}:${service_port}"
      echo "  Selector: ${selector}"
      echo
      echo "Request flow:"
      echo "  Client"
      echo "    → ${host}${path}"
      echo "    → Traefik Ingress Controller"
      echo "    → Ingress ${NAMESPACE}/${INGRESS_NAME}"
      echo "    → Service ${NAMESPACE}/${service}:${service_port}"
      echo "    → Endpoints / EndpointSlices"
      echo "    → Backend Pod(s)"

    done

  echo
  echo "============================================================"
  echo "End of Kubernetes Ingress route trace"
  echo "============================================================"

} | tee "${OUTPUT_FILE}"

echo
echo "Route trace saved to: ${OUTPUT_FILE}"
