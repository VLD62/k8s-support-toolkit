# Kubernetes Argo CD Deployment Inventory

A collection of read-only Bash scripts for reviewing how Argo CD applications are configured and deployed in a Kubernetes environment.

The toolset helps platform and support engineers understand the relationship between:

* Argo CD Applications and AppProjects;
* Git repositories and source paths;
* Kubernetes clusters and namespaces;
* synchronization policies;
* managed Kubernetes resources;
* application health and deployment history.

## Repository Structure

```text
k8s-argocd-deployment-model/
├── k8s-argocd-deployment-model_README.md
└── scripts/
    ├── 01_argocd_environment_inventory.sh
    ├── 02_argocd_applications_projects_inventory.sh
    ├── 03_argocd_sync_health_diagnostics.sh
    ├── 04_argocd_operational_configuration_inventory.sh
    └── run_all_argocd_inventory.sh
```

## Scripts

### `01_argocd_environment_inventory.sh`

Collects a general overview of the Argo CD installation, including:

* Kubernetes context and versions;
* Argo CD namespace and CRDs;
* Applications, AppProjects, and ApplicationSets;
* Argo CD workloads, pods, services, and ingress resources;
* deployed container images;
* configuration resource inventory.

### `02_argocd_applications_projects_inventory.sh`

Documents the application deployment configuration, including:

* Git repositories and target revisions;
* source paths and deployment types;
* destination clusters and namespaces;
* manual or automated synchronization;
* pruning and self-healing settings;
* managed Kubernetes resources;
* AppProject destinations and permissions.

### `03_argocd_sync_health_diagnostics.sh`

Collects operational synchronization information, including:

* current sync and health status;
* last synchronization operation;
* operation errors and resource results;
* OutOfSync resources;
* Application conditions;
* deployment history and events.

### `04_argocd_operational_configuration_inventory.sh`

Collects operational configuration metadata, including:

* Argo CD server and ingress configuration;
* authentication configuration presence;
* RBAC summary;
* registered repository and cluster connections;
* Application metadata;
* synchronization options;
* AppProject configuration.

Secret credential values are not collected.

### `run_all_argocd_inventory.sh`

Runs all inventory scripts sequentially and creates a combined execution log.

## Usage

Run an individual script:

```bash
./scripts/01_argocd_environment_inventory.sh
```

Run the complete inventory:

```bash
./scripts/run_all_argocd_inventory.sh
```

Use a different Argo CD namespace:

```bash
ARGOCD_NAMESPACE=my-argocd \
./scripts/run_all_argocd_inventory.sh
```

Use a custom output directory:

```bash
OUTPUT_DIR=/tmp/argocd-inventory \
./scripts/run_all_argocd_inventory.sh
```

## Output

The scripts generate timestamped text reports in the configured output directory.

Generated reports may contain environment-specific information and should not be committed to source control.

Recommended `.gitignore` entry:

```gitignore
k8s-argocd-deployment-model/output/
```

## Requirements

* Bash
* `kubectl`
* access to the target Kubernetes cluster
* read access to the Argo CD namespace and resources
* standard Unix command-line utilities

The Argo CD CLI is not required.

## Safety

The scripts are read-only. They do not:

* synchronize Applications;
* enable pruning;
* delete Kubernetes resources;
* modify Argo CD configuration;
* change Git repositories;
* display secret credential values.

