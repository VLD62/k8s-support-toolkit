# Kubernetes Baseline Inventory Scripts

This folder contains reusable read-only scripts for collecting Kubernetes baseline inventory information.

The scripts are intended to support operational documentation, troubleshooting readiness, and cluster overview activities. They can be reused against another Kubernetes context or cluster.

## Scripts Overview

| Script | Purpose |
|---|---|
| `01_context_access_inventory.sh` | Collects the current Kubernetes context, cluster API information, client/server version, and validates read access to key resources. |
| `02_nodes_inventory.sh` | Collects node information, including roles, status, Kubernetes version, OS, kernel, container runtime, labels, taints, and capacity details. |
| `03_namespaces_workloads_inventory.sh` | Collects namespaces, pods, workload controllers, services, namespace labels, and pod count per namespace. |
| `04_traefik_inventory.sh` | Collects Traefik ingress controller resources, including DaemonSet, pod, service, node selector, ports, and exposure details. |
| `05_argocd_inventory.sh` | Collects Argo CD resources, including pods, deployments, StatefulSet, services, ingress, and ConfigMaps. |
| `06_storage_inventory.sh` | Collects StorageClasses, PersistentVolumeClaims, PersistentVolumes, and basic storage usage overview. |
| `07_ingress_service_inventory.sh` | Collects IngressClasses, Ingress resources, services, NodePort/LoadBalancer services, and endpoint information. |
| `run_all_baseline_inventory.sh` | Runs all baseline inventory scripts and stores the collected output in the selected output directory. |

## Usage

Run all inventory scripts:

```bash
./scripts/run_all_baseline_inventory.sh
```

Run all inventory scripts with a custom output directory:

```bash
./scripts/run_all_baseline_inventory.sh outputs-example-cluster
```

Run an individual script:

```bash
./scripts/01_context_access_inventory.sh outputs-example-cluster
```

## Notes

- The scripts execute read-only `kubectl` commands only.
- No production-impacting changes are performed.
- The active Kubernetes context is used.
- Before running against another cluster, verify the current context:

```bash
kubectl config current-context
```

To switch context:

```bash
kubectl config use-context <context-name>
```
