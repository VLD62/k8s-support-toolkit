# Kubernetes Workload Troubleshooting Runbook

## 1. Purpose

This runbook provides a repeatable, read-only troubleshooting workflow for Kubernetes workloads.

It is intended for DevOps engineers, platform engineers, application support teams, and developers who need to investigate workload failures without modifying cluster resources.

The runbook covers the diagnostic path from namespace-level triage to workload, Pod, container, dependency, storage, and node-level investigation.

---

## 2. Scope

The runbook supports troubleshooting of:

- Deployments
- ReplicaSets
- StatefulSets
- DaemonSets
- Jobs and CronJobs
- Pods and init containers
- Services and EndpointSlices
- ConfigMaps and Secrets metadata
- PersistentVolumeClaims
- Resource usage and namespace events

Common conditions covered include:

- `Pending`
- `CrashLoopBackOff`
- `ImagePullBackOff`
- `ErrImagePull`
- `CreateContainerConfigError`
- `RunContainerError`
- `OOMKilled`
- failing init containers
- failed readiness, liveness, or startup probes
- unavailable Deployment replicas
- failed or stalled rollouts
- repeated container restarts
- missing Service endpoints
- missing ConfigMaps, Secrets, or PVCs
- insufficient CPU, memory, or storage resources

---

## 3. Safety Principles

The scripts in this directory are diagnostic and read-only.

They do not:

- delete or restart Pods
- scale workloads
- modify Deployments or StatefulSets
- change ConfigMaps or Secrets
- perform rollout restarts
- execute commands inside application containers
- decode or export Secret values

Secret names and metadata may be listed because they are useful when validating workload dependencies. Secret data is never displayed.

Generated reports may still contain internal resource names, image names, IP addresses, node names, and infrastructure details. Store and share the output according to the applicable information-handling and security policies.

---

## 4. Troubleshooting Flow

Use the following investigation sequence:

```text
Namespace
  ↓
Workload controller
  ↓
Replica and rollout status
  ↓
Pod phase and readiness
  ↓
Container state and restart history
  ↓
Events
  ↓
Current and previous logs
  ↓
Probes and resource configuration
  ↓
ConfigMap, Secret, and volume dependencies
  ↓
Service and EndpointSlice dependencies
  ↓
Node health and resource pressure
```

Do not assume that a Pod is healthy only because its phase is `Running`.

A running Pod may still:

- be unready
- contain a failing sidecar
- have a high restart count
- have terminated previously with an error
- be excluded from Service endpoints
- consume resources close to its configured limits

---

## 5. Directory Structure

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

The `outputs/` directory contains generated diagnostic reports and should not be committed to Git.

Recommended `.gitignore` entry:

```gitignore
k8s-workload-troubleshooting/outputs/
```

---

## 6. Script 01: Namespace Workload Overview

### Purpose

`01_namespace_workload_overview.sh` performs the initial namespace-level triage.

It answers the following questions:

- Is the namespace accessible?
- Which workload controllers exist?
- Are the expected replicas available?
- Which Pods are running, pending, failed, or completed?
- Are all containers ready?
- Have any containers restarted?
- Are warning events present?
- Do Services have EndpointSlices?
- Are referenced configuration and storage resources present?
- Is resource usage available through the Metrics API?

### Usage

Run the script from the `k8s-workload-troubleshooting` directory:

```bash
./scripts/01_namespace_workload_overview.sh <namespace>
```

Examples:

```bash
./scripts/01_namespace_workload_overview.sh application-platform
./scripts/01_namespace_workload_overview.sh example-namespace
```

An alternative output directory can be supplied:

```bash
./scripts/01_namespace_workload_overview.sh example-namespace ./custom-output
```

### Generated output

The script creates a timestamped report:

```text
outputs/01_namespace_workload_overview_<namespace>_<timestamp>.txt
```

Example:

```text
outputs/01_namespace_workload_overview_example-namespace_<timestamp>.txt
```

---

## 7. Interpreting the Namespace Overview

### 7.1 Workload controllers

Compare the desired and available replica counts.

Healthy Deployment example:

```text
READY   UP-TO-DATE   AVAILABLE
1/1     1            1
```

Investigate when:

- `READY` is lower than desired
- `AVAILABLE` is lower than desired
- `UP-TO-DATE` is lower than desired
- a StatefulSet has unavailable replicas
- a DaemonSet does not have the expected number of ready Pods
- a Job has failed or does not complete

Historical ReplicaSets with zero desired replicas are normally retained as Deployment revision history. They are not automatically a failure.

### 7.2 Pod phase

Typical phases:

| Phase | Meaning | Initial action |
|---|---|---|
| `Pending` | Pod has not started successfully | Review scheduling events, PVCs, image pulls, and init containers |
| `Running` | Pod is assigned and at least one container is running | Verify readiness, restart count, and container states |
| `Succeeded` | All containers exited successfully | Usually expected for Jobs |
| `Failed` | At least one container terminated unsuccessfully and will not restart | Review termination reason and logs |
| `Unknown` | Pod status cannot be obtained reliably | Check node and API connectivity |

The `STATUS` column shown by `kubectl get pods` can also display container-level reasons such as `CrashLoopBackOff`, `ImagePullBackOff`, or `Init:Error`.

### 7.3 Readiness

A Pod can be in the `Running` phase but still be unready.

Examples:

```text
1/1
```

All declared containers are ready.

```text
2/3
```

One of three containers is not ready. Investigate the individual container state and readiness probe.

### 7.4 Container restarts

A restart count greater than zero is not always an active outage, but it must be understood.

Check:

- which container restarted
- the last termination reason
- the exit code
- when the last restart occurred
- previous container logs
- whether restarts continue to increase

Typical reasons include:

- application process failure
- failed liveness probe
- `OOMKilled`
- configuration or dependency failure
- temporary external service outage
- node restart or container runtime interruption

### 7.5 Events

Events are useful for recent scheduling, image, volume, probe, and runtime failures.

Important event reasons include:

- `FailedScheduling`
- `FailedMount`
- `FailedAttachVolume`
- `FailedPull`
- `BackOff`
- `Unhealthy`
- `Evicted`
- `Preempted`

An empty event list does not prove that no failure occurred. Kubernetes events are retained for a limited period, so older evidence may already have expired.

### 7.6 Services and EndpointSlices

A Service should normally have one or more ready backend endpoints.

Investigate when:

- a Service has no EndpointSlice
- an EndpointSlice exists but contains no addresses
- the endpoint address does not match an expected Pod
- the Service selector does not match Pod labels
- target ports do not match container ports

### 7.7 Configuration dependencies

The overview lists ConfigMaps and Secret metadata to confirm whether expected dependency objects exist.

The next diagnostic level should verify:

- object names referenced by the workload
- key names referenced through `env`, `envFrom`, or volumes
- optional versus mandatory references
- volume mount paths

Secret values must not be decoded as part of routine evidence collection.

### 7.8 Persistent storage

PVCs should normally be in the `Bound` state.

Investigate:

- `Pending` PVCs
- incorrect StorageClass
- unavailable capacity
- access-mode mismatch
- failed volume mounts
- zone or node affinity conflicts

### 7.9 Resource usage

When Metrics Server is available, compare current CPU and memory consumption with the workload's requests and limits.

High current memory combined with an `OOMKilled` termination reason strongly suggests that the memory limit or application memory behavior requires investigation.

The absence of metrics may mean:

- Metrics Server is unavailable
- the metrics API is not ready
- access is denied by RBAC
- the Pod is too new to have metrics

---

## 8. Validation Approach

The scripts should be validated against representative non-production or approved test workloads before operational adoption.

Recommended validation scenarios include:

### Healthy namespace

Confirm that the scripts correctly report:

- all expected Pods in `Running`
- all declared containers ready
- no unexpected restart history
- populated EndpointSlices
- available metrics when the Metrics API is enabled
- bound PVCs where persistent storage is used

### Pod with restart history

Use a test Pod or approved workload with known restart history to confirm that the workflow reports:

- the exact restarted container
- restart count
- previous termination reason
- previous exit code
- current and previous logs
- current Pod readiness

This validates that a currently healthy Pod can still retain useful historical failure evidence.

### Service dependency path

Validate a Service with a known backend and confirm the relationship:

```text
Service selector
  ↓
Matching ready Pod
  ↓
Pod IP present in EndpointSlice
  ↓
Service targetPort matches the application port
```

### Evidence bundle

Run the complete bundle collector and verify:

- all requested diagnostic stages complete
- the status manifest lists successful, failed, and skipped steps
- generated files are present
- checksums validate after extraction
- the archive can be reviewed independently of the original repository

Use placeholders rather than real internal names in published documentation:

```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --all-containers=true
kubectl logs <pod-name> -n <namespace> --all-containers=true --previous
```

For multi-container Pods:

```bash
kubectl logs <pod-name> -n <namespace> -c <container-name>
kubectl logs <pod-name> -n <namespace> -c <container-name> --previous
```

---

## 9. Initial Triage Decision Table

| Observation | Likely investigation path |
|---|---|
| Deployment unavailable replicas | Deployment conditions, rollout status, ReplicaSet and Pods |
| Pod `Pending` | Events, scheduler reason, PVC, resource requests, node selectors and tolerations |
| `CrashLoopBackOff` | Container state, previous logs, command, configuration, probes |
| `ImagePullBackOff` | Image name, registry reachability, imagePullSecrets |
| `CreateContainerConfigError` | Missing ConfigMap, Secret, key, or invalid container configuration |
| `OOMKilled` | Memory usage, requests, limits, application memory behavior |
| Pod running but not ready | Readiness probe, dependency availability, container logs |
| Pod has restarts but is currently healthy | Last termination state and previous logs |
| Service has no endpoints | Service selector, Pod labels, readiness, target port |
| PVC `Pending` | StorageClass, capacity, access mode, provisioner events |
| No recent events | Continue with Pod description, status fields, logs, and monitoring history |

---

## 10. Evidence Collection Guidelines

When escalating a workload problem, collect at least:

- Kubernetes context
- namespace
- workload kind and name
- affected Pod names
- current Pod and container states
- restart counts
- last termination reasons and exit codes
- relevant warning events
- current and previous logs
- resource requests and limits
- current CPU and memory usage when available
- referenced ConfigMaps, Secrets, and PVC names
- Service selectors and EndpointSlices
- node name for affected Pods
- timestamps and approximate incident start time

Do not include decoded credentials, tokens, private keys, or application secrets.

---

## 11. Included Scripts

### `02_workload_diagnostics.sh`

Provides controller-focused investigation:

- workload description
- desired, current, ready, and available replicas
- workload conditions
- rollout status
- owner relationships
- selected Pods
- workload-related events
- container images, probes, requests, limits, and dependencies

### `03_pod_diagnostics.sh`

Provides Pod and container-focused investigation:

- Pod description
- init container and application container states
- termination reason and exit code
- current and previous logs
- probes
- environment references
- volume mounts
- resource configuration
- node assignment
- Pod-related events

### `04_service_dependency_check.sh`

Provides Service path investigation:

- Service selectors
- matching Pods
- Pod readiness
- EndpointSlices
- Service ports
- target ports
- backend consistency

### `05_collect_troubleshooting_bundle.sh`

Creates a combined evidence bundle:

- namespace overview
- workload diagnostics
- Pod diagnostics
- Service dependency information
- timestamped output directory
- archive suitable for controlled support escalation

---

## 12. Operational Boundary

This runbook focuses on diagnosis and evidence collection.

Corrective actions such as the following must be handled separately and only after the failure cause is understood:

- rollout restart
- scaling
- image update
- configuration change
- resource-limit adjustment
- PVC modification
- Pod deletion
- node drain
- rollback

The troubleshooting scripts must remain safe to run by support users with read-only Kubernetes permissions.
