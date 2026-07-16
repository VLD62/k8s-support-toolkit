#!/usr/bin/env bash

set -u

OUTPUT_DIR="outputs"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_FILE="${OUTPUT_DIR}/03_service_exposure_inventory_${TIMESTAMP}.txt"
SUMMARY_FILE="${OUTPUT_DIR}/03_service_exposure_summary_${TIMESTAMP}.csv"
INGRESS_BACKENDS_FILE="${OUTPUT_DIR}/03_ingress_backend_services_${TIMESTAMP}.csv"

mkdir -p "${OUTPUT_DIR}"

{
  echo "============================================================"
  echo "Kubernetes Service Exposure Inventory"
  echo "Generated at: $(date)"
  echo "Kubernetes context: $(kubectl config current-context 2>/dev/null || echo 'N/A')"
  echo "============================================================"
  echo

  echo "## 1. All Services overview"
  kubectl get services -A -o wide 2>/dev/null || true
  echo

  echo "## 2. Service types summary"
  kubectl get services -A --no-headers 2>/dev/null | awk '
    {
      count[$3]++
    }
    END {
      print "TYPE COUNT"
      for (type in count) {
        print type, count[type]
      }
    }
  ' || true
  echo

  echo "## 3. ClusterIP Services"
  kubectl get services -A --field-selector spec.type=ClusterIP -o wide 2>/dev/null || true
  echo

  echo "## 4. NodePort Services"
  kubectl get services -A --field-selector spec.type=NodePort -o wide 2>/dev/null || true
  echo

  echo "## 5. LoadBalancer Services"
  kubectl get services -A --field-selector spec.type=LoadBalancer -o wide 2>/dev/null || true
  echo

  echo "## 6. ExternalName Services"
  kubectl get services -A --field-selector spec.type=ExternalName -o wide 2>/dev/null || true
  echo

  echo "## 7. Services referenced by Ingress resources"
  echo "namespace,ingress,host,path,service,service_port"

  for ns in $(kubectl get ingress -A --no-headers 2>/dev/null | awk '{print $1}' | sort -u); do
    for ing in $(kubectl get ingress -n "${ns}" --no-headers 2>/dev/null | awk '{print $1}'); do
      kubectl get ingress -n "${ns}" "${ing}" \
        -o jsonpath='{range .spec.rules[*]}{.host}{"|"}{range .http.paths[*]}{.path}{"|"}{.backend.service.name}{"|"}{.backend.service.port.name}{.backend.service.port.number}{"\n"}{end}{end}' \
        2>/dev/null | while IFS='|' read -r host path service service_port; do
          echo "${ns},${ing},${host},${path},${service},${service_port}"
        done
    done
  done
  echo

  echo "## 8. Detailed backend Services referenced by Ingress resources"

  for ns in $(kubectl get ingress -A --no-headers 2>/dev/null | awk '{print $1}' | sort -u); do
    for ing in $(kubectl get ingress -n "${ns}" --no-headers 2>/dev/null | awk '{print $1}'); do
      kubectl get ingress -n "${ns}" "${ing}" \
        -o jsonpath='{range .spec.rules[*]}{.host}{"|"}{range .http.paths[*]}{.path}{"|"}{.backend.service.name}{"|"}{.backend.service.port.name}{.backend.service.port.number}{"\n"}{end}{end}' \
        2>/dev/null | while IFS='|' read -r host path service service_port; do

          echo "------------------------------------------------------------"
          echo "Ingress: ${ns}/${ing}"
          echo "Host: ${host}"
          echo "Path: ${path}"
          echo "Backend Service: ${ns}/${service}"
          echo "Backend Service Port: ${service_port}"
          echo "------------------------------------------------------------"

          echo
          echo "### Service"
          kubectl get service -n "${ns}" "${service}" -o wide 2>/dev/null || true
          echo

          echo "### Service details"
          kubectl describe service -n "${ns}" "${service}" 2>/dev/null || true
          echo

          echo "### Endpoints"
          kubectl get endpoints -n "${ns}" "${service}" -o wide 2>/dev/null || true
          echo

          echo "### EndpointSlices"
          kubectl get endpointslices -n "${ns}" -l kubernetes.io/service-name="${service}" -o wide 2>/dev/null || true
          echo

        done
    done
  done

  echo "## 9. Services without endpoints"
  echo "Note: Some Services are expected to have no endpoints, for example ExternalName Services or headless/service-discovery related Services."
  echo

  for ns in $(kubectl get services -A --no-headers 2>/dev/null | awk '{print $1}' | sort -u); do
    for svc in $(kubectl get services -n "${ns}" --no-headers 2>/dev/null | awk '{print $1}'); do
      endpoints="$(kubectl get endpoints -n "${ns}" "${svc}" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || true)"
      svc_type="$(kubectl get service -n "${ns}" "${svc}" -o jsonpath='{.spec.type}' 2>/dev/null || true)"

      if [ -z "${endpoints}" ]; then
        echo "${ns}/${svc} type=${svc_type}"
      fi
    done
  done
  echo

  echo "============================================================"
  echo "End of Kubernetes Service exposure inventory"
  echo "============================================================"

} | tee "${OUTPUT_FILE}"

echo "namespace,service,type,cluster_ip,external_ip,ports,node_ports,selector" > "${SUMMARY_FILE}"

for ns in $(kubectl get services -A --no-headers 2>/dev/null | awk '{print $1}' | sort -u); do
  for svc in $(kubectl get services -n "${ns}" --no-headers 2>/dev/null | awk '{print $1}'); do

    svc_type="$(kubectl get service -n "${ns}" "${svc}" -o jsonpath='{.spec.type}' 2>/dev/null || true)"
    cluster_ip="$(kubectl get service -n "${ns}" "${svc}" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
    external_ip="$(kubectl get service -n "${ns}" "${svc}" -o jsonpath='{.status.loadBalancer.ingress[*].ip}{.spec.externalIPs[*]}' 2>/dev/null || true)"
    ports="$(kubectl get service -n "${ns}" "${svc}" -o jsonpath='{range .spec.ports[*]}{.name}:{.port}->{.targetPort}/{.protocol}{";"}{end}' 2>/dev/null || true)"
    node_ports="$(kubectl get service -n "${ns}" "${svc}" -o jsonpath='{range .spec.ports[*]}{.nodePort}{";"}{end}' 2>/dev/null || true)"
    selector="$(kubectl get service -n "${ns}" "${svc}" -o jsonpath='{.spec.selector}' 2>/dev/null || true)"

    echo "\"${ns}\",\"${svc}\",\"${svc_type}\",\"${cluster_ip}\",\"${external_ip}\",\"${ports}\",\"${node_ports}\",\"${selector}\"" >> "${SUMMARY_FILE}"

  done
done

echo "namespace,ingress,host,path,service,service_port" > "${INGRESS_BACKENDS_FILE}"

for ns in $(kubectl get ingress -A --no-headers 2>/dev/null | awk '{print $1}' | sort -u); do
  for ing in $(kubectl get ingress -n "${ns}" --no-headers 2>/dev/null | awk '{print $1}'); do
    kubectl get ingress -n "${ns}" "${ing}" \
      -o jsonpath='{range .spec.rules[*]}{.host}{"|"}{range .http.paths[*]}{.path}{"|"}{.backend.service.name}{"|"}{.backend.service.port.name}{.backend.service.port.number}{"\n"}{end}{end}' \
      2>/dev/null | while IFS='|' read -r host path service service_port; do
        echo "\"${ns}\",\"${ing}\",\"${host}\",\"${path}\",\"${service}\",\"${service_port}\"" >> "${INGRESS_BACKENDS_FILE}"
      done
  done
done

echo
echo "Inventory saved to: ${OUTPUT_FILE}"
echo "Service summary CSV saved to: ${SUMMARY_FILE}"
echo "Ingress backend services CSV saved to: ${INGRESS_BACKENDS_FILE}"
