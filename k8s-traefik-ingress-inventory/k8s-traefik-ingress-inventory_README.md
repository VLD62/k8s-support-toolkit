# Kubernetes Traefik Ingress Inventory Scripts

This folder contains read-only helper scripts used to collect and document information about the Traefik ingress and Kubernetes service exposure model.

The scripts support the story:

```text
Document Traefik ingress and service exposure model
```

The goal is to understand how external application routes are handled in the Kubernetes cluster through:

```text
External URL
  → Traefik
  → Kubernetes Ingress
  → Service
  → Endpoints / EndpointSlices
  → Backend Pods
```

## Folder Structure

```text
k8s-traefik-ingress-inventory/
├── scripts/
│   ├── 01_traefik_inventory.sh
│   ├── 02_ingress_inventory.sh
│   ├── 03_service_exposure_inventory.sh
│   ├── 04_route_trace.sh
│   └── 05_troubleshooting_commands.sh
├── outputs/
└── README.md
```

## Safety

All scripts are read-only.

They do not:

```text
create resources
update resources
delete resources
restart workloads
change routing
modify production configuration
```

The scripts only use commands such as:

```bash
kubectl get
kubectl describe
kubectl logs
kubectl config current-context
```

## Prerequisites

Before running the scripts, make sure that:

```text
kubectl is installed
cluster access is configured
the correct Kubernetes context is selected
```

Check the current context:

```bash
kubectl config current-context
```

Example context:

```text
example-cluster
```

## Scripts

### 01_traefik_inventory.sh

Collects information about the Traefik ingress controller.

It checks:

```text
Traefik namespace
Traefik pods
Traefik DaemonSet or Deployment
Traefik Service
IngressClass
Traefik ConfigMaps and Secrets
Traefik CRDs
Traefik Middleware / IngressRoute / TLS resources, if available
Traefik-related events
```

Run:

```bash
./scripts/01_traefik_inventory.sh
```

Example output:

```text
outputs/01_traefik_inventory_<timestamp>.txt
```

---

### 02_ingress_inventory.sh

Collects information about Kubernetes Ingress resources across namespaces.

It checks:

```text
Ingress namespace
Ingress name
IngressClass
Host
Path
Backend Service
Backend Service port
TLS configuration
Annotations
Full Ingress YAML
```

Run:

```bash
./scripts/02_ingress_inventory.sh
```

Example outputs:

```text
outputs/02_ingress_inventory_<timestamp>.txt
outputs/02_ingress_summary_<timestamp>.csv
```

The CSV file can be used to create tables in documentation or Confluence.

---

### 03_service_exposure_inventory.sh

Collects information about Kubernetes Services and service exposure types.

It checks:

```text
All Services across namespaces
Service type summary
ClusterIP Services
NodePort Services
LoadBalancer Services
ExternalName Services
Services referenced by Ingress resources
Backend Service details
Endpoints
EndpointSlices
Services without Endpoints
```

Run:

```bash
./scripts/03_service_exposure_inventory.sh
```

Example outputs:

```text
outputs/03_service_exposure_inventory_<timestamp>.txt
outputs/03_service_exposure_summary_<timestamp>.csv
outputs/03_ingress_backend_services_<timestamp>.csv
```

This helps document the high-level service exposure model, for example:

```text
External access → Traefik NodePort Service
Application routing → Kubernetes Ingress
Backend access → ClusterIP Services
Pod routing → Endpoints / EndpointSlices
```

---

### 04_route_trace.sh

Traces one selected application route end-to-end.

It maps:

```text
Host / Path
  → Ingress
  → Service
  → Endpoints
  → EndpointSlices
  → Backend Pods
```

Usage:

```bash
./scripts/04_route_trace.sh
```

Example route:

```text
example-gitops example-gitops-server
```

Run for a specific route:

```bash
./scripts/04_route_trace.sh <namespace> <ingress-name>
```

Examples:

```bash
./scripts/04_route_trace.sh example-gitops example-gitops-server
./scripts/04_route_trace.sh example-monitoring example-monitoring
./scripts/04_route_trace.sh example-worker example-worker-ingress
./scripts/04_route_trace.sh example-data example-data-api
```

Example output:

```text
outputs/04_route_trace_<namespace>_<ingress-name>_<timestamp>.txt
```

This script is used to document at least one complete application route from external URL to backend Pod.

---

### 05_troubleshooting_commands.sh

Generates a markdown troubleshooting runbook for a selected Ingress route.

It includes commands for:

```text
Traefik checks
Ingress checks
Service checks
Endpoints checks
EndpointSlices checks
Backend Pod checks
TLS checks
Common routing symptoms and possible causes
Useful operational one-liners
Live read-only validation for the selected route
```

Usage:

```bash
./scripts/05_troubleshooting_commands.sh
```

Example route:

```text
example-gitops example-gitops-server
```

Run for a specific route:

```bash
./scripts/05_troubleshooting_commands.sh <namespace> <ingress-name>
```

Examples:

```bash
./scripts/05_troubleshooting_commands.sh example-gitops example-gitops-server
./scripts/05_troubleshooting_commands.sh example-monitoring example-monitoring
./scripts/05_troubleshooting_commands.sh example-worker example-worker-ingress
./scripts/05_troubleshooting_commands.sh example-data example-data-api
```

Example output:

```text
outputs/05_troubleshooting_commands_<namespace>_<ingress-name>_<timestamp>.md
```

The generated markdown file can be reused directly in Confluence or project documentation.

## Recommended Execution Order

Run the scripts in this order:

```bash
./scripts/01_traefik_inventory.sh
./scripts/02_ingress_inventory.sh
./scripts/03_service_exposure_inventory.sh
./scripts/04_route_trace.sh example-gitops example-gitops-server
./scripts/05_troubleshooting_commands.sh example-gitops example-gitops-server
```

Optional additional route checks:

```bash
./scripts/04_route_trace.sh example-monitoring example-monitoring
./scripts/04_route_trace.sh example-worker example-worker-ingress
./scripts/04_route_trace.sh example-data example-data-api

./scripts/05_troubleshooting_commands.sh example-monitoring example-monitoring
./scripts/05_troubleshooting_commands.sh example-worker example-worker-ingress
./scripts/05_troubleshooting_commands.sh example-data example-data-api
```

## Output Files

All generated files are written to:

```text
outputs/
```

The files are timestamped so that multiple inventory runs can be kept for comparison.

Example:

```text
outputs/01_traefik_inventory_<timestamp>.txt
outputs/02_ingress_inventory_<timestamp>.txt
outputs/02_ingress_summary_<timestamp>.csv
outputs/03_service_exposure_inventory_<timestamp>.txt
outputs/03_service_exposure_summary_<timestamp>.csv
outputs/04_route_trace_example-gitops_example-gitops-server_<timestamp>.txt
outputs/05_troubleshooting_commands_example-gitops_example-gitops-server_<timestamp>.md
```

## Documentation Target

The collected information is intended to support the documentation page:

```text
Kubernetes Traefik Ingress and Service Exposure Model
```

Suggested documentation sections:

```text
Traefik Ingress Controller Overview
Ingress Resource Overview
Service Exposure Model
Application Route Mapping
Troubleshooting Commands and Operational Runbooks
Findings, Gaps, and Improvement Opportunities
```

## Acceptance Criteria Mapping

| Acceptance Criteria                                                                                         | Covered By                              |
| ----------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| Traefik ingress controller namespace, pods, services, and configuration resources are identified.           | `01_traefik_inventory.sh`               |
| Existing Ingress resources are reviewed across relevant namespaces.                                         | `02_ingress_inventory.sh`               |
| At least one application route is mapped end-to-end from host/path to Service, Endpoints, and backend Pods. | `04_route_trace.sh`                     |
| Service exposure types are documented at high level.                                                        | `03_service_exposure_inventory.sh`      |
| Common troubleshooting commands for Ingress, Services, Endpoints, and Pods are documented.                  | `05_troubleshooting_commands.sh`        |
| Potential gaps, risks, or improvement opportunities are captured.                                           | Script outputs and documentation        |
| Findings are documented in Confluence or project documentation.                                             | Confluence page / project documentation |
| No production-impacting changes are performed as part of this story.                                        | All scripts are read-only               |
