# Kubernetes Storage and PVC Review

Reusable Bash scripts for reviewing Kubernetes StorageClasses, PersistentVolumes, PersistentVolumeClaims, workload storage mappings, and runtime storage health.

The toolset is intended for operational reviews, troubleshooting, capacity validation, and documentation of Kubernetes persistent storage environments.

## Repository Structure

```text
k8s-storage-pvc-review/
├── scripts/
│   ├── 01_storage_classes_inventory.sh
│   ├── 02_pv_pvc_inventory.sh
│   ├── 03_pvc_workload_mapping.sh
│   ├── 04_storage_health_checks.sh
│   └── run_all_storage_review.sh
└── k8s-storage-pvc-review_README.md
```

Runtime outputs are written to an `outputs/` directory and should not be committed to source control.

## Scripts

### `01_storage_classes_inventory.sh`

Collects information about available Kubernetes StorageClasses and CSI drivers.

The script reports:

* provisioners
* reclaim policies
* volume binding modes
* volume expansion support
* default StorageClass configuration
* StorageClass parameters
* installed CSI drivers

It also identifies potentially relevant configuration conditions such as:

* no default StorageClass
* multiple default StorageClasses
* `Immediate` volume binding
* `Retain` reclaim policies
* disabled volume expansion

### `02_pv_pvc_inventory.sh`

Inventories PersistentVolumes and PersistentVolumeClaims across the cluster.

The script reports:

* PV and PVC status
* requested and allocated capacity
* StorageClass usage
* access and volume modes
* reclaim policies
* CSI volume handles
* claim-to-volume relationships
* VolumeAttachment resources

It also detects:

* pending or lost PVCs
* available, released, failed, or pending PVs
* PVCs without an explicit StorageClass
* unsuccessful storage resource states

### `03_pvc_workload_mapping.sh`

Maps PVCs to the Pods and higher-level workloads that consume them.

The script identifies:

* consuming Pods
* Deployments, StatefulSets, Jobs, and other workload owners
* container mount paths
* init container mounts
* StatefulSet volume claim templates
* PVCs without current Pod references
* Pods referencing missing PVCs

A PVC without a current Pod reference is not automatically considered orphaned. It may belong to a scaled-down or temporarily stopped workload.

### `04_storage_health_checks.sh`

Performs runtime storage health validation.

The script checks:

* abnormal PV and PVC states
* unsuccessful VolumeAttachments
* storage-related warning events
* CSI controller and node component health
* node storage topology
* mounted filesystem utilization
* high filesystem usage
* VolumeSnapshot API availability
* StorageClass policy configuration

Runtime filesystem usage is collected with `kubectl exec` and `df`.

A failed runtime check does not automatically indicate a storage failure. The container may not include the `df` command, or access to `pods/exec` may be restricted.

### `run_all_storage_review.sh`

Executes all review scripts in sequence and creates:

* an execution log
* a Markdown status summary
* the individual inventory and health-check outputs

## Requirements

* Bash
* `kubectl`
* access to a Kubernetes cluster
* permission to list cluster-scoped and namespace-scoped storage resources

The runtime filesystem checks additionally require permission to use:

```text
pods/exec
```

## Usage

Run an individual script:

```bash
cd k8s-storage-pvc-review

./scripts/01_storage_classes_inventory.sh
./scripts/02_pv_pvc_inventory.sh
./scripts/03_pvc_workload_mapping.sh
./scripts/04_storage_health_checks.sh
```

Run the complete review:

```bash
./scripts/run_all_storage_review.sh
```

Use a custom output directory:

```bash
OUTPUT_DIR=/tmp/k8s-storage-review \
./scripts/run_all_storage_review.sh
```

## Output Files

Generated files use timestamped names:

```text
outputs/
├── 00_storage_review_execution_YYYYMMDD_HHMMSS.log
├── 00_storage_review_status_YYYYMMDD_HHMMSS.md
├── 01_storage_classes_inventory_YYYYMMDD_HHMMSS.txt
├── 02_pv_pvc_inventory_YYYYMMDD_HHMMSS.txt
├── 03_pvc_workload_mapping_YYYYMMDD_HHMMSS.txt
└── 04_storage_health_checks_YYYYMMDD_HHMMSS.txt
```

Output files can contain cluster names, namespaces, workloads, node names, volume identifiers, and other environment-specific information.

They should not be committed to a public repository.

Recommended `.gitignore` entry:

```gitignore
k8s-storage-pvc-review/outputs/
```

## Review Guidance

The generated output should be reviewed for:

* PVCs that are not bound
* released or failed PVs
* orphaned or unused storage resources
* unsuccessful volume attachments
* high filesystem utilization
* unexpected StorageClass selection
* unsuitable reclaim policies
* topology conflicts
* missing backup or snapshot capabilities
* oversized or undersized volume requests

## Safety

The scripts perform read-only Kubernetes inventory operations, except for runtime checks that execute the read-only `df` command inside selected containers.

The scripts do not:

* create or delete storage resources
* modify StorageClasses
* resize PVCs
* detach volumes
* create snapshots
* change workload configuration

Review all findings before making storage configuration changes.

