# Kubernetes Support Toolkit

A collection of reusable Bash scripts, templates, runbooks, and operational
documentation for Kubernetes platform inventory, ingress analysis, workload
troubleshooting, RBAC review, namespace onboarding, storage review, Argo CD
deployment analysis, and daily support activities.

The repository is intended to support DevOps engineers, platform engineers,
application support teams, and application owners during operational reviews,
environment analysis, access reviews, onboarding, and incident investigation.

## Repository Structure

```text
k8s-support-toolkit/
├── k8s-baseline-inventory/
│   ├── k8s_baseline_inventory_scripts_README.md
│   └── scripts/
├── k8s-traefik-ingress-inventory/
│   ├── k8s-traefik-ingress-inventory_README.md
│   └── scripts/
├── k8s-workload-troubleshooting/
│   ├── k8s-workload-troubleshooting_README.md
│   ├── docs/
│   │   └── kubernetes-workload-troubleshooting-runbook.md
│   └── scripts/
├── k8s-rbac-model/
│   ├── k8s-rbac-model_README.md
│   └── scripts/
├── k8s-namespace-onboarding/
│   ├── k8s-namespace-onboarding_README.md
│   ├── templates/
│   ├── examples/
│   └── manifests/
├── k8s-storage-pvc-review/
│   ├── k8s-storage-pvc-review_README.md
│   └── scripts/
├── k8s-argocd-deployment-model/
│   ├── k8s-argocd-deployment-model_README.md
│   └── scripts/
├── k8s-operational-command-cheat-sheet/
│   └── k8s-operational-command-cheat-sheet.md
├── .gitignore
├── LICENSE
└── README.md
```

## Toolsets

### Kubernetes Baseline Inventory

Location:

```text
k8s-baseline-inventory/
```

Collects a structured overview of the Kubernetes environment, including:

- current Kubernetes context and access;
- cluster nodes;
- namespaces and workloads;
- Traefik deployment;
- Argo CD deployment;
- storage classes and persistent volumes;
- ingress and service exposure.

Run the complete inventory:

```bash
cd k8s-baseline-inventory
./scripts/run_all_baseline_inventory.sh
```

More information:

```text
k8s-baseline-inventory/k8s_baseline_inventory_scripts_README.md
```

---

### Traefik Ingress Inventory

Location:

```text
k8s-traefik-ingress-inventory/
```

Provides scripts for analyzing the Kubernetes ingress and service-exposure
model, including:

- Traefik controller inventory;
- Kubernetes Ingress resources;
- service exposure methods;
- ingress-to-service route tracing;
- generated troubleshooting command references.

Run scripts individually:

```bash
cd k8s-traefik-ingress-inventory/scripts

./01_traefik_inventory.sh
./02_ingress_inventory.sh
./03_service_exposure_inventory.sh
./04_route_trace.sh
./05_troubleshooting_commands.sh
```

Some scripts require namespace, ingress, or service arguments. See the
toolset-specific README for usage examples.

More information:

```text
k8s-traefik-ingress-inventory/k8s-traefik-ingress-inventory_README.md
```

---

### Kubernetes Workload Troubleshooting

Location:

```text
k8s-workload-troubleshooting/
```

Provides reusable diagnostics for Kubernetes workloads and Pods, including:

- namespace workload overview;
- Deployment, StatefulSet, DaemonSet, Job, and CronJob diagnostics;
- Pod status, events, logs, probes, and container state;
- Service, endpoint, and dependency checks;
- automated troubleshooting bundle collection;
- checksums and execution status;
- a reusable workload troubleshooting runbook.

Example bundle collection:

```bash
cd k8s-workload-troubleshooting/scripts

./05_collect_troubleshooting_bundle.sh \
  --namespace example-app \
  --workload-kind statefulset \
  --workload-name example-worker \
  --pod example-worker-0 \
  --service example-worker
```

More information:

```text
k8s-workload-troubleshooting/k8s-workload-troubleshooting_README.md
```

Troubleshooting runbook:

```text
k8s-workload-troubleshooting/docs/kubernetes-workload-troubleshooting-runbook.md
```

---

### Kubernetes RBAC Model

Location:

```text
k8s-rbac-model/
```

Provides read-only inventory scripts and documentation for reviewing the
Kubernetes authentication and authorization model, including:

- Kubernetes Roles and ClusterRoles;
- RoleBindings and ClusterRoleBindings;
- users, groups, and ServiceAccounts;
- effective permission validation;
- highly privileged binding review;
- Kubernetes API server authentication and authorization configuration;
- external identity-provider and authorization integration;
- duplicated, excessive, and security-sensitive permissions;
- operational support access-model analysis.

Run the inventory scripts individually:

```bash
cd k8s-rbac-model/scripts

./01_rbac_inventory.sh
./02_authentication_authorization_inventory.sh
./03_keystone_policy_model_inventory.sh
./04_keystone_permission_summary.sh
```

The scripts do not modify Kubernetes RBAC objects or external authorization
policies.

More information:

```text
k8s-rbac-model/k8s-rbac-model_README.md
```

---

### Kubernetes Namespace Onboarding

Location:

```text
k8s-namespace-onboarding/
```

Provides reusable templates, checklists, examples, and Kubernetes manifests for
standardizing namespace onboarding.

The module covers:

- application and namespace ownership;
- environment and workload requirements;
- CPU, memory, and storage requirements;
- RBAC and ServiceAccount requirements;
- networking and service exposure;
- monitoring, logging, recovery, and support responsibilities;
- namespace readiness validation;
- example namespace, quota, limit, ServiceAccount, and RoleBinding manifests.

Main files:

```text
k8s-namespace-onboarding/templates/namespace-onboarding-template.md
k8s-namespace-onboarding/templates/namespace-readiness-checklist.md
k8s-namespace-onboarding/examples/example-namespace-onboarding.md
k8s-namespace-onboarding/manifests/
```

Validate the example manifests after replacing all placeholders:

```bash
cd k8s-namespace-onboarding
kubectl apply --dry-run=client -f manifests/
```

More information:

```text
k8s-namespace-onboarding/k8s-namespace-onboarding_README.md
```

---

### Kubernetes Storage and PVC Review

Location:

```text
k8s-storage-pvc-review/
```

Provides read-only inventory and health-check scripts for Kubernetes persistent
storage, including:

- StorageClass and CSI driver inventory;
- PersistentVolume and PersistentVolumeClaim status;
- PVC-to-workload mapping;
- VolumeAttachment checks;
- storage-related warning events;
- CSI component health;
- mounted filesystem utilization;
- StorageClass policy review.

Run the complete review:

```bash
cd k8s-storage-pvc-review
./scripts/run_all_storage_review.sh
```

Run an individual script:

```bash
./scripts/01_storage_classes_inventory.sh
./scripts/02_pv_pvc_inventory.sh
./scripts/03_pvc_workload_mapping.sh
./scripts/04_storage_health_checks.sh
```

More information:

```text
k8s-storage-pvc-review/k8s-storage-pvc-review_README.md
```

---

### Kubernetes Argo CD Deployment Inventory

Location:

```text
k8s-argocd-deployment-model/
```

Provides read-only inventory scripts for reviewing how Argo CD applications are
configured and deployed.

The module covers:

- Argo CD installation and workload inventory;
- Applications, AppProjects, and ApplicationSets;
- Git repositories, target revisions, and source paths;
- destination clusters and namespaces;
- synchronization, pruning, and self-healing settings;
- managed Kubernetes resources;
- application health, sync status, history, and conditions;
- operational configuration and connection metadata.

Run the complete inventory:

```bash
cd k8s-argocd-deployment-model
./scripts/run_all_argocd_inventory.sh
```

Use a custom Argo CD namespace:

```bash
ARGOCD_NAMESPACE=my-argocd \
./scripts/run_all_argocd_inventory.sh
```

More information:

```text
k8s-argocd-deployment-model/k8s-argocd-deployment-model_README.md
```

---

### Kubernetes Operational Command Cheat Sheet

Location:

```text
k8s-operational-command-cheat-sheet/
```

Provides a reusable command reference for daily Kubernetes operations and
support activities, including:

- context and namespace checks;
- workload inspection;
- logs, events, and container diagnostics;
- Service and ingress troubleshooting;
- RBAC permission checks;
- storage investigation;
- Traefik operations;
- Helm commands;
- Argo CD support commands.

Open the command reference:

```text
k8s-operational-command-cheat-sheet/k8s-operational-command-cheat-sheet.md
```

## Requirements

The scripts are designed for Linux environments and require:

- Bash;
- `kubectl`;
- Python 3 for selected inventory scripts;
- access to a Kubernetes cluster;
- a configured Kubernetes context;
- standard Linux utilities such as `grep`, `awk`, `sed`, `tar`, and
  `sha256sum`.

Verify cluster access before running the scripts:

```bash
kubectl config current-context
kubectl cluster-info
kubectl auth can-i get pods --all-namespaces
```

Individual modules may require additional permissions, such as access to
cluster-scoped resources or `pods/exec`. Review the module-specific README
before execution.

## Script Permissions

Make all scripts executable:

```bash
find . -type f -name "*.sh" -exec chmod +x {} \;
```

Verify permissions:

```bash
find . -type f -name "*.sh" -ls
```

## Usage Guidelines

Run the scripts with a Kubernetes identity that has sufficient read permissions
for the required namespaces and resources.

Avoid using highly privileged credentials unless they are necessary for the
investigation.

Permission checks executed with a cluster administrator identity confirm
administrative reachability but do not represent the permissions of a normal
developer, viewer, or support engineer.

Review generated files before sharing them outside the organization. Diagnostic
and inventory output may contain:

- internal hostnames;
- cluster, context, namespace, workload, and Pod names;
- container images;
- ServiceAccount names;
- usernames and groups;
- project or tenant identifiers;
- internal endpoints;
- IP addresses;
- configuration values;
- environment metadata;
- authorization policy details;
- log content.

Secrets should not normally be collected by the scripts, but generated output
must still be treated as operationally sensitive.

## Generated Output

Generated reports, logs, checksums, archives, troubleshooting bundles, and
inventory output are excluded from Git through `.gitignore`.

Before committing changes, verify the repository state:

```bash
git status
git status --ignored
```

Do not commit:

- kubeconfig files;
- private keys or certificates;
- `.env` files;
- Kubernetes Secret manifests;
- ServiceAccount tokens;
- generated troubleshooting bundles;
- cluster inventory output;
- authentication and authorization inventory output;
- unredacted external authorization policies;
- application logs.

## Development Guidelines

When adding a new toolset:

1. Create a dedicated directory.
2. Store executable scripts under a `scripts/` directory when applicable.
3. Add a toolset-specific README.
4. Use numbered script names when execution order matters.
5. Keep generated output outside source directories where possible.
6. Update the root `.gitignore` when introducing generated file patterns.
7. Update this README with the new toolset.

Recommended structure for a script-based module:

```text
new-toolset/
├── new-toolset_README.md
└── scripts/
    ├── 01_first_check.sh
    ├── 02_second_check.sh
    └── run_all.sh
```

## Scope

The toolkit currently covers:

- Kubernetes cluster baseline inventory;
- Traefik ingress and service-exposure analysis;
- Kubernetes workload and Pod troubleshooting;
- Kubernetes RBAC and access-model review;
- external authentication and authorization analysis;
- Kubernetes namespace onboarding;
- Kubernetes StorageClass, PV, and PVC review;
- Argo CD application deployment inventory;
- Kubernetes operational command references.

Additional Kubernetes operational tools can be added as separate modules while
keeping the repository structure consistent.

## License

This project is licensed under the MIT License.

See the [LICENSE](LICENSE) file for details.
