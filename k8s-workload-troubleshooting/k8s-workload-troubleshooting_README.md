 Kubernetes Workload Troubleshooting

Read-only Kubernetes troubleshooting utilities for namespace, workload, Pod, container, Service, and EndpointSlice diagnostics.

The scripts provide a structured troubleshooting flow and generate timestamped evidence that can be reviewed locally or attached to an incident, support request, or escalation.

## Purpose

This folder helps engineers investigate common Kubernetes workload problems without changing cluster resources.

The workflow narrows an issue through the following levels:

```text
Namespace
  ↓
Workload controller
  ↓
Pod and containers
  ↓
Service and EndpointSlices
  ↓
Troubleshooting bundle
```

Typical use cases include:

- Pods that are not Running or Ready
- container restart history
- rollout or replica inconsistencies
- failed init containers
- current or previous container errors
- missing Service backends
- selector and label mismatches
- missing or not-ready EndpointSlices
- incorrect Service or target ports
- configuration, storage, or node context collection
- evidence collection for escalation

## Directory Structure

```text
k8s-workload-troubleshooting/
├── README.md
├── docs/
│   └── kubernetes-workload-troubleshooting-runbook.md
├── scripts/
│   ├── 01_namespace_workload_overview.sh
│   ├── 02_workload_diagnostics.sh
│   ├── 03_pod_diagnostics.sh
│   ├── 04_service_dependency_check.sh
│   └── 05_collect_troubleshooting_bundle.sh
└── outputs/
```

Generated output files are stored under `outputs/` and should not be committed.

Recommended `.gitignore` entry:

```gitignore
k8s-workload-troubleshooting/outputs/
```

## Prerequisites

Required:

- Bash
- `kubectl`
- access to a Kubernetes cluster
- permission to read the target namespace and resources

Optional:

- Metrics Server access for `kubectl top`
- `sha256sum` for bundle integrity checks
- `tar` for compressed bundle creation

Check the active context before collecting evidence:

```bash
kubectl config current-context
```

Check client and server versions:

```bash
kubectl version
```

The `kubectl` client should normally remain within one minor version of the Kubernetes API server.

## Quick Start

Make the scripts executable:

```bash
chmod +x scripts/*.sh
```

Run a namespace overview:

```bash
./scripts/01_namespace_workload_overview.sh example-app
```

Inspect a workload:

```bash
./scripts/02_workload_diagnostics.sh \
  example-app \
  statefulset \
  example-worker
```

Inspect a Pod:

```bash
./scripts/03_pod_diagnostics.sh \
  example-app \
  example-worker-0
```

Validate a Service backend path:

```bash
./scripts/04_service_dependency_check.sh \
  example-app \
  example-worker
```

Collect a complete bundle:

```bash
./scripts/05_collect_troubleshooting_bundle.sh \
  --namespace example-app \
  --workload statefulset example-worker \
  --service example-worker \
  --archive
```

## Troubleshooting Flow

### 1. Start at Namespace Level

Use Script 01 to identify:

- unhealthy Pods
- not-ready Pods
- restart history
- warning events
- Services and EndpointSlices
- ConfigMaps and Secrets
- PVC state
- current resource usage

```bash
./scripts/01_namespace_workload_overview.sh <namespace>
```

### 2. Inspect the Workload Controller

Use Script 02 when a Deployment, StatefulSet, DaemonSet, Job, or CronJob needs further inspection.

```bash
./scripts/02_workload_diagnostics.sh \
  <namespace> \
  <workload-kind> \
  <workload-name>
```

Supported workload kinds:

- `deployment`
- `statefulset`
- `daemonset`
- `job`
- `cronjob`

Common aliases such as `deploy`, `sts`, `ds`, and `cj` are also accepted.

### 3. Inspect a Specific Pod

Use Script 03 after identifying a Pod with restart history, readiness problems, or container errors.

```bash
./scripts/03_pod_diagnostics.sh \
  <namespace> \
  <pod-name>
```

This script collects current and previous logs per container and identifies:

- the exact restarted container
- restart count
- previous termination reason
- previous exit code
- current state
- init-container state
- requests and limits
- probe configuration
- ConfigMap and Secret references
- volumes and mounts
- assigned node conditions

### 4. Validate the Service Backend Path

Use Script 04 to validate:

```text
Service
  ↓
Selector
  ↓
Matching Pods
  ↓
Pod readiness
  ↓
EndpointSlices
  ↓
Endpoint addresses
  ↓
Service port and targetPort
```

```bash
./scripts/04_service_dependency_check.sh \
  <namespace> \
  <service-name>
```

### 5. Collect an Escalation Bundle

Use Script 05 to combine the previous diagnostics into one timestamped directory.

```bash
./scripts/05_collect_troubleshooting_bundle.sh \
  --namespace <namespace> \
  [--workload <kind> <name>] \
  [--pod <pod-name>]... \
  [--service <service-name>]... \
  [--log-tail <lines>] \
  [--archive]
```

## Script Reference

### `01_namespace_workload_overview.sh`

Provides a namespace-level operational overview.

Usage:

```bash
./scripts/01_namespace_workload_overview.sh \
  <namespace> \
  [output-directory]
```

Collects:

- namespace status
- RBAC access checks
- Deployments
- ReplicaSets
- StatefulSets
- DaemonSets
- Jobs
- CronJobs
- Pods and container state
- restart history
- warning and recent events
- Services
- EndpointSlices
- ConfigMaps
- Secrets
- PVCs
- Pod resource metrics
- diagnostic summary

Example output:

```text
outputs/01_namespace_workload_overview_example-app_<timestamp>.txt
```

### `02_workload_diagnostics.sh`

Provides controller-level diagnostics.

Usage:

```bash
./scripts/02_workload_diagnostics.sh \
  <namespace> \
  <workload-kind> \
  <workload-name> \
  [output-directory]
```

Collects:

- controller status
- replicas and revisions
- observed generation
- rollout status
- workload conditions
- full workload description
- matching Pods
- Pod and container state
- workload and Pod events
- resource usage
- diagnostic summary

Example output:

```text
outputs/02_workload_diagnostics_example-app_statefulset_example-worker_<timestamp>.txt
```

### `03_pod_diagnostics.sh`

Provides detailed Pod and per-container diagnostics.

Usage:

```bash
./scripts/03_pod_diagnostics.sh \
  <namespace> \
  <pod-name> \
  [output-directory] \
  [log-tail]
```

Default log tail:

```text
200 lines per container
```

Collects:

- Pod phase and readiness
- ownership and scheduling
- Pod conditions
- init and application containers
- current and previous states
- exit codes
- termination reasons
- restart count per container
- probes
- requests and limits
- configuration references
- volumes and mounts
- Pod description
- events
- current logs
- previous logs for restarted containers
- Pod metrics
- assigned node overview
- diagnostic summary

Example output:

```text
outputs/03_pod_diagnostics_example-app_example-worker-0_<timestamp>.txt
```

### `04_service_dependency_check.sh`

Validates the complete Service backend path.

Usage:

```bash
./scripts/04_service_dependency_check.sh \
  <namespace> \
  <service-name> \
  [output-directory]
```

Collects:

- Service type and ClusterIP
- selectors
- Service ports and target ports
- matching Pods
- Pod readiness and restart history
- declared container ports
- EndpointSlices
- endpoint readiness
- legacy Endpoints
- Pod-to-endpoint consistency
- Service and EndpointSlice events
- NetworkPolicies
- diagnostic summary

The script supports:

- standard ClusterIP Services
- headless Services
- ExternalName Services
- selectorless Services

Example output:

```text
outputs/04_service_dependency_check_example-app_example-worker_<timestamp>.txt
```

### `05_collect_troubleshooting_bundle.sh`

Orchestrates the complete troubleshooting workflow.

Usage:

```bash
./scripts/05_collect_troubleshooting_bundle.sh \
  --namespace <namespace> \
  [--workload <kind> <name>] \
  [--pod <pod-name>]... \
  [--service <service-name>]... \
  [--output-dir <directory>] \
  [--log-tail <lines>] \
  [--archive]
```

Arguments:

| Argument | Description |
|---|---|
| `--namespace`, `-n` | Target namespace |
| `--workload`, `-w` | Workload kind and name |
| `--pod`, `-p` | Pod to diagnose; may be repeated |
| `--service`, `-s` | Service to check; may be repeated |
| `--output-dir`, `-o` | Root output directory |
| `--log-tail` | Log lines collected per container |
| `--archive` | Create a `.tar.gz` archive |
| `--help`, `-h` | Show usage information |

The script can automatically discover a Pod when exactly one Pod matches a supplied Deployment, StatefulSet, DaemonSet, or Job.

When multiple Pods match, Pod diagnostics are skipped unless specific Pods are supplied with `--pod`.

## Bundle Structure

A complete bundle has the following structure:

```text
outputs/
├── troubleshooting_bundle_<namespace>_<timestamp>/
│   ├── 00_bundle_context.txt
│   ├── 00_bundle_execution.log
│   ├── 00_bundle_status.md
│   ├── 01_namespace_workload_overview_...
│   ├── 02_workload_diagnostics_...
│   ├── 03_pod_diagnostics_...
│   ├── 04_service_dependency_check_...
│   └── checksums.sha256
└── troubleshooting_bundle_<namespace>_<timestamp>.tar.gz
```

### Bundle Context

`00_bundle_context.txt` records:

- generation time
- Kubernetes context
- namespace
- workload
- Pods
- Services
- log-tail setting
- client and server versions

### Bundle Status

`00_bundle_status.md` summarizes:

- requested diagnostic scope
- successful steps
- failed steps
- skipped steps
- generated files
- handling guidance

### Checksums

After extracting a bundle:

```bash
cd troubleshooting_bundle_<namespace>_<timestamp>

sha256sum --check checksums.sha256
```

Expected result:

```text
00_bundle_context.txt: OK
00_bundle_status.md: OK
01_namespace_workload_overview_...: OK
02_workload_diagnostics_...: OK
03_pod_diagnostics_...: OK
04_service_dependency_check_...: OK
```

## Example Scenarios

### Namespace Triage

```bash
./scripts/05_collect_troubleshooting_bundle.sh \
  --namespace example-app
```

### StatefulSet and Headless Service

```bash
./scripts/05_collect_troubleshooting_bundle.sh \
  --namespace example-app \
  --workload statefulset example-worker \
  --service example-worker \
  --archive
```

### Deployment and Explicit Pod

```bash
./scripts/05_collect_troubleshooting_bundle.sh \
  --namespace example-app \
  --workload deployment example-api \
  --pod example-api-7d9f8c6b5-x2abc \
  --service example-api \
  --archive
```

### Multiple Pods and Services

```bash
./scripts/05_collect_troubleshooting_bundle.sh \
  --namespace example-app \
  --pod example-worker-0 \
  --pod example-api-7d9f8c6b5-x2abc \
  --service example-worker \
  --service example-api \
  --archive
```

### GitOps Application Validation

```bash
./scripts/05_collect_troubleshooting_bundle.sh \
  --namespace example-gitops \
  --workload deployment example-gitops-server \
  --service example-gitops-server \
  --archive
```

## Validation Summary

The workflow was functionally validated against representative Deployment and
StatefulSet workloads in a non-production test environment.

Validation covered:

- namespace-level health and restart history;
- controller rollout and condition reporting;
- per-container current and previous logs;
- Service selector and EndpointSlice validation;
- portable evidence bundle generation;
- distinction between current health and historical failures.

Environment-specific workload names, incidents, endpoints, and collected
outputs are intentionally excluded from this repository.

## Interpretation Guidance

### Running Does Not Mean No History

A Pod may be:

```text
Running
Ready
```

and still have meaningful restart history.

Always check:

- restart count
- previous state
- previous reason
- previous exit code
- previous logs

### Events May Expire

The absence of current events does not prove that no earlier problem occurred.

Use:

- previous container state
- previous logs
- restart timestamps
- application logs
- monitoring history

### EndpointSlices Are the Primary Backend Source

Modern Kubernetes versions use EndpointSlices as the primary Service backend representation.

Legacy `Endpoints` output is collected for compatibility, but EndpointSlices should be used for current analysis.

### Resource Metrics Are Context, Not Proof

High CPU or memory usage may help explain an issue, but a single `kubectl top` snapshot is not sufficient to prove a root cause.

Use monitoring history when available.

## Safety and Operational Boundaries

All scripts are designed to perform read-only operations.

They do not:

- restart Pods
- delete resources
- scale workloads
- modify manifests
- patch objects
- execute commands inside containers
- decode Secret values

The scripts do use `kubectl describe` and collect application logs.

Generated evidence may therefore contain:

- internal resource names
- image names
- IP addresses
- node names
- ConfigMap and Secret reference names
- literal non-secret environment values
- application log content

Always review generated files before sharing them outside the intended support channel.

## Documentation

The complete operational runbook is available at:

```text
docs/kubernetes-workload-troubleshooting-runbook.md
```

It includes:

- troubleshooting decision guidance
- script-level documentation
- interpretation examples
- generic validation and interpretation examples
- escalation evidence requirements
- operational boundaries