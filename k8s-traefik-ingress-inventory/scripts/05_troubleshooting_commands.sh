#!/usr/bin/env bash

set -u

OUTPUT_DIR="outputs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

NAMESPACE="${1:-}"
INGRESS_NAME="${2:-}"

if [[ -z "${NAMESPACE}" || -z "${INGRESS_NAME}" ]]; then
  echo "Usage: 05_troubleshooting_commands.sh <namespace> <ingress-name>" >&2
  echo "Example: 05_troubleshooting_commands.sh example-app example-ingress" >&2
  exit 1
fi

OUTPUT_FILE="${OUTPUT_DIR}/05_troubleshooting_commands_${NAMESPACE}_${INGRESS_NAME}_${TIMESTAMP}.md"

mkdir -p "${OUTPUT_DIR}"

get_first_route_field() {
  local jsonpath="$1"

  kubectl get ingress -n "${NAMESPACE}" "${INGRESS_NAME}" \
    -o jsonpath="${jsonpath}" 2>/dev/null || true
}

HOST="$(get_first_route_field '{.spec.rules[0].host}')"
PATH_VALUE="$(get_first_route_field '{.spec.rules[0].http.paths[0].path}')"
SERVICE_NAME="$(get_first_route_field '{.spec.rules[0].http.paths[0].backend.service.name}')"
SERVICE_PORT_NAME="$(get_first_route_field '{.spec.rules[0].http.paths[0].backend.service.port.name}')"
SERVICE_PORT_NUMBER="$(get_first_route_field '{.spec.rules[0].http.paths[0].backend.service.port.number}')"

if [ -n "${SERVICE_PORT_NAME}" ]; then
  SERVICE_PORT="${SERVICE_PORT_NAME}"
else
  SERVICE_PORT="${SERVICE_PORT_NUMBER}"
fi

SERVICE_SELECTOR="$(kubectl get service -n "${NAMESPACE}" "${SERVICE_NAME}" \
  -o jsonpath='{.spec.selector}' 2>/dev/null \
  | sed -e 's/^map\[//' -e 's/\]$//' -e 's/:/=/g' -e 's/ /,/g')"

{
  echo "# Kubernetes Ingress and Service Troubleshooting Runbook"
  echo
  echo "Generated at: \`$(date)\`"
  echo
  echo "Kubernetes context: \`$(kubectl config current-context 2>/dev/null || echo 'N/A')\`"
  echo
  echo "Reviewed route:"
  echo
  echo "\`\`\`text"
  echo "https://${HOST}${PATH_VALUE}"
  echo "\`\`\`"
  echo
  echo "| Item | Value |"
  echo "|---|---|"
  echo "| Namespace | \`${NAMESPACE}\` |"
  echo "| Ingress | \`${INGRESS_NAME}\` |"
  echo "| Host | \`${HOST}\` |"
  echo "| Path | \`${PATH_VALUE}\` |"
  echo "| Backend Service | \`${SERVICE_NAME}\` |"
  echo "| Backend Service Port | \`${SERVICE_PORT}\` |"
  echo "| Service selector | \`${SERVICE_SELECTOR}\` |"
  echo
  echo "---"
  echo
  echo "## Request Flow"
  echo
  echo "\`\`\`text"
  echo "Client / Browser"
  echo "  → ${HOST}${PATH_VALUE}"
  echo "  → Traefik Ingress Controller"
  echo "  → Ingress: ${NAMESPACE}/${INGRESS_NAME}"
  echo "  → Service: ${NAMESPACE}/${SERVICE_NAME}:${SERVICE_PORT}"
  echo "  → Endpoints / EndpointSlices"
  echo "  → Backend Pod(s)"
  echo "\`\`\`"
  echo
  echo "---"
  echo
  echo "## 1. Check Traefik"
  echo
  echo "### Check Traefik namespace, pods, DaemonSet, and Service"
  echo
  echo "\`\`\`bash"
  echo "kubectl get ns | grep -i traefik"
  echo "kubectl get pods -n traefik -o wide"
  echo "kubectl get daemonset -n traefik -o wide"
  echo "kubectl get svc -n traefik -o wide"
  echo "kubectl describe svc -n traefik traefik"
  echo "\`\`\`"
  echo
  echo "### Check Traefik logs"
  echo
  echo "\`\`\`bash"
  echo "kubectl logs -n traefik -l app.kubernetes.io/name=traefik --tail=100"
  echo "\`\`\`"
  echo
  echo "### Check IngressClass"
  echo
  echo "\`\`\`bash"
  echo "kubectl get ingressclass -o wide"
  echo "kubectl describe ingressclass traefik"
  echo "\`\`\`"
  echo
  echo "---"
  echo
  echo "## 2. Check Ingress"
  echo
  echo "### Check all Ingress resources"
  echo
  echo "\`\`\`bash"
  echo "kubectl get ingress -A -o wide"
  echo "\`\`\`"
  echo
  echo "### Check selected Ingress"
  echo
  echo "\`\`\`bash"
  echo "kubectl get ingress -n ${NAMESPACE} ${INGRESS_NAME} -o wide"
  echo "kubectl describe ingress -n ${NAMESPACE} ${INGRESS_NAME}"
  echo "kubectl get ingress -n ${NAMESPACE} ${INGRESS_NAME} -o yaml"
  echo "\`\`\`"
  echo
  echo "### Check host, path, backend Service, and TLS"
  echo
  echo "\`\`\`bash"
  echo "kubectl get ingress -n ${NAMESPACE} ${INGRESS_NAME} \\"
  echo "  -o jsonpath='{.spec.rules[*].host}{\"\\n\"}{.spec.rules[*].http.paths[*].path}{\"\\n\"}{.spec.rules[*].http.paths[*].backend.service.name}{\"\\n\"}{.spec.tls[*].secretName}{\"\\n\"}'"
  echo "\`\`\`"
  echo
  echo "---"
  echo
  echo "## 3. Check Backend Service"
  echo
  echo "### Check Service"
  echo
  echo "\`\`\`bash"
  echo "kubectl get svc -n ${NAMESPACE} ${SERVICE_NAME} -o wide"
  echo "kubectl describe svc -n ${NAMESPACE} ${SERVICE_NAME}"
  echo "kubectl get svc -n ${NAMESPACE} ${SERVICE_NAME} -o yaml"
  echo "\`\`\`"
  echo
  echo "### Check Service selector"
  echo
  echo "\`\`\`bash"
  echo "kubectl get svc -n ${NAMESPACE} ${SERVICE_NAME} \\"
  echo "  -o jsonpath='{.spec.selector}{\"\\n\"}'"
  echo "\`\`\`"
  echo
  echo "---"
  echo
  echo "## 4. Check Endpoints and EndpointSlices"
  echo
  echo "### Check Endpoints"
  echo
  echo "\`\`\`bash"
  echo "kubectl get endpoints -n ${NAMESPACE} ${SERVICE_NAME} -o wide"
  echo "kubectl describe endpoints -n ${NAMESPACE} ${SERVICE_NAME}"
  echo "kubectl get endpoints -n ${NAMESPACE} ${SERVICE_NAME} -o yaml"
  echo "\`\`\`"
  echo
  echo "### Check EndpointSlices"
  echo
  echo "\`\`\`bash"
  echo "kubectl get endpointslices -n ${NAMESPACE} \\"
  echo "  -l kubernetes.io/service-name=${SERVICE_NAME} -o wide"
  echo
  echo "kubectl get endpointslices -n ${NAMESPACE} \\"
  echo "  -l kubernetes.io/service-name=${SERVICE_NAME} -o yaml"
  echo "\`\`\`"
  echo
  echo "---"
  echo
  echo "## 5. Check Backend Pods"
  echo
  echo "### Check Pods selected by the Service"
  echo
  echo "\`\`\`bash"
  if [ -n "${SERVICE_SELECTOR}" ]; then
    echo "kubectl get pods -n ${NAMESPACE} -l ${SERVICE_SELECTOR} -o wide"
    echo "kubectl describe pods -n ${NAMESPACE} -l ${SERVICE_SELECTOR}"
  else
    echo "# Service selector could not be detected automatically."
    echo "kubectl get pods -n ${NAMESPACE} -o wide"
  fi
  echo "\`\`\`"
  echo
  echo "### Check Pod logs"
  echo
  echo "\`\`\`bash"
  if [ -n "${SERVICE_SELECTOR}" ]; then
    echo "kubectl logs -n ${NAMESPACE} -l ${SERVICE_SELECTOR} --tail=100"
  else
    echo "kubectl logs -n ${NAMESPACE} <pod-name> --tail=100"
  fi
  echo "\`\`\`"
  echo
  echo "---"
  echo
  echo "## 6. Check TLS"
  echo
  echo "### Check TLS secret referenced by Ingress"
  echo
  echo "\`\`\`bash"
  echo "kubectl get ingress -n ${NAMESPACE} ${INGRESS_NAME} -o jsonpath='{.spec.tls[*].secretName}{\"\\n\"}'"
  echo "kubectl get secret -n ${NAMESPACE}"
  echo "kubectl describe secret -n ${NAMESPACE} <tls-secret-name>"
  echo "\`\`\`"
  echo
  echo "### Decode certificate validity, if needed"
  echo
  echo "\`\`\`bash"
  echo "kubectl get secret -n ${NAMESPACE} <tls-secret-name> -o jsonpath='{.data.tls\\.crt}' \\"
  echo "  | base64 -d \\"
  echo "  | openssl x509 -noout -subject -issuer -dates"
  echo "\`\`\`"
  echo
  echo "---"
  echo
  echo "## 7. Common Issues and Checks"
  echo
  echo "| Symptom | Possible Cause | Useful Checks |"
  echo "|---|---|---|"
  echo "| URL returns 404 | Host/path does not match any Ingress rule | Check Ingress host, path, pathType, and IngressClass |"
  echo "| URL returns 502 / 503 | Service has no ready backend endpoints | Check Service selector, Endpoints, EndpointSlices, and Pod readiness |"
  echo "| TLS warning or certificate error | Missing, wrong, or expired TLS secret | Check Ingress TLS section and referenced secret |"
  echo "| Service exists but no endpoints | Selector does not match Pods or Pods are not Ready | Compare Service selector with Pod labels |"
  echo "| Pod exists but traffic fails | Wrong targetPort, app not listening, or container issue | Check Service targetPort, Pod ports, and Pod logs |"
  echo "| Route works internally but not externally | NodePort, DNS, firewall, or upstream routing issue | Check Traefik Service, NodePort, DNS, and external routing |"
  echo "| Path-based app loads but assets fail | Application may not be configured for sub-path | Check app base URL, root URL, rewrite/strip-prefix config |"
  echo "| Middleware expected but not applied | Wrong annotation or missing Middleware resource | Check Traefik middleware annotations and CRD resources |"
  echo
  echo "---"
  echo
  echo "## 8. Useful One-liners"
  echo
  echo "### Show all exposed application routes"
  echo
  echo "\`\`\`bash"
  echo "kubectl get ingress -A \\"
  echo "  -o custom-columns='NAMESPACE:.metadata.namespace,INGRESS:.metadata.name,CLASS:.spec.ingressClassName,HOSTS:.spec.rules[*].host,PATHS:.spec.rules[*].http.paths[*].path,SERVICE:.spec.rules[*].http.paths[*].backend.service.name'"
  echo "\`\`\`"
  echo
  echo "### Show Services without Endpoints"
  echo
  echo "\`\`\`bash"
  echo "for ns in \$(kubectl get svc -A --no-headers | awk '{print \$1}' | sort -u); do"
  echo "  for svc in \$(kubectl get svc -n \"\$ns\" --no-headers | awk '{print \$1}'); do"
  echo "    endpoints=\$(kubectl get endpoints -n \"\$ns\" \"\$svc\" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)"
  echo "    type=\$(kubectl get svc -n \"\$ns\" \"\$svc\" -o jsonpath='{.spec.type}' 2>/dev/null)"
  echo "    if [ -z \"\$endpoints\" ]; then"
  echo "      echo \"\$ns/\$svc type=\$type\""
  echo "    fi"
  echo "  done"
  echo "done"
  echo "\`\`\`"
  echo
  echo "### Show Traefik related resources"
  echo
  echo "\`\`\`bash"
  echo "kubectl get pods,svc,daemonset,deploy,cm,secret -n traefik -o wide"
  echo "kubectl get ingressclass"
  echo "kubectl get crd | grep -i traefik"
  echo "\`\`\`"
  echo
  echo "---"
  echo
  echo "## 9. Live Read-only Check for Selected Route"
  echo
  echo "### Ingress"
  echo
  echo "\`\`\`text"
  kubectl get ingress -n "${NAMESPACE}" "${INGRESS_NAME}" -o wide 2>/dev/null || true
  echo "\`\`\`"
  echo
  echo "### Service"
  echo
  echo "\`\`\`text"
  kubectl get svc -n "${NAMESPACE}" "${SERVICE_NAME}" -o wide 2>/dev/null || true
  echo "\`\`\`"
  echo
  echo "### Endpoints"
  echo
  echo "\`\`\`text"
  kubectl get endpoints -n "${NAMESPACE}" "${SERVICE_NAME}" -o wide 2>/dev/null || true
  echo "\`\`\`"
  echo
  echo "### EndpointSlices"
  echo
  echo "\`\`\`text"
  kubectl get endpointslices -n "${NAMESPACE}" \
    -l kubernetes.io/service-name="${SERVICE_NAME}" \
    -o wide 2>/dev/null || true
  echo "\`\`\`"
  echo
  echo "### Backend Pods"
  echo
  echo "\`\`\`text"
  if [ -n "${SERVICE_SELECTOR}" ]; then
    kubectl get pods -n "${NAMESPACE}" -l "${SERVICE_SELECTOR}" -o wide 2>/dev/null || true
  else
    echo "Service selector was not detected automatically."
  fi
  echo "\`\`\`"
  echo
  echo "---"
  echo
  echo "## 10. Notes"
  echo
  echo "- This runbook is based on read-only Kubernetes checks."
  echo "- No production-impacting changes are performed by this script."
  echo "- Commands that inspect logs, resources, Endpoints, and manifests are safe for operational troubleshooting."
  echo "- Any change actions, such as editing Ingress, Service, Middleware, TLS secrets, or Deployments, should follow the normal change process."

} | tee "${OUTPUT_FILE}"

echo
echo "Troubleshooting runbook saved to: ${OUTPUT_FILE}"
