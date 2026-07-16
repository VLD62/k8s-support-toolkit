#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-outputs}"
mkdir -p "${OUT_DIR}"

echo "Collecting Kubernetes context and access scope..."
echo "Output directory: ${OUT_DIR}"

kubectl config current-context | tee "${OUT_DIR}/01-current-context.txt"

kubectl config get-contexts | tee "${OUT_DIR}/02-contexts.txt"

kubectl cluster-info | tee "${OUT_DIR}/03-cluster-info.txt"

{
  echo "Resource,Command,Result"

  echo -n "Nodes,kubectl auth can-i get nodes,"
  kubectl auth can-i get nodes

  echo -n "Namespaces,kubectl auth can-i get namespaces,"
  kubectl auth can-i get namespaces

  echo -n "Pods across namespaces,kubectl auth can-i get pods --all-namespaces,"
  kubectl auth can-i get pods --all-namespaces

  echo -n "Ingress resources,kubectl auth can-i get ingress --all-namespaces,"
  kubectl auth can-i get ingress --all-namespaces

  echo -n "StorageClasses,kubectl auth can-i get storageclasses,"
  kubectl auth can-i get storageclasses

  echo -n "PVCs across namespaces,kubectl auth can-i get persistentvolumeclaims --all-namespaces,"
  kubectl auth can-i get persistentvolumeclaims --all-namespaces
} | tee "${OUT_DIR}/04-access-scope.csv"

kubectl version -o yaml 2>&1 | tee "${OUT_DIR}/05-kubernetes-version.txt"

echo
echo "Done. Context and access inventory collected in: ${OUT_DIR}"
