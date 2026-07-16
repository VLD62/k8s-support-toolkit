# Kubernetes RBAC Model

## Purpose

This module inventories and documents the Kubernetes authentication and
authorization model used for platform administration, application workloads,
and operational support.

The collected information is intended to help platform and application support
teams:

- understand how access to a Kubernetes cluster is granted;
- distinguish Kubernetes RBAC permissions from external authorization policies;
- identify excessive, duplicated, or unexpected privileges;
- validate permissions required for common support activities;
- design safer read-only, troubleshooting, operator, and administrator access
  levels.

## Scope

The module covers:

- Kubernetes users, groups, and ServiceAccounts;
- `Role`, `ClusterRole`, `RoleBinding`, and `ClusterRoleBinding` resources;
- effective permissions of the active Kubernetes identity;
- Kubernetes API server authentication and authorization configuration;
- external identity-provider authentication and authorization integration;
- configured external authorization policies;
- high-risk and duplicated permissions;
- operational support access-model analysis.

The module is inventory and documentation only. It does not modify Kubernetes
RBAC objects or external authorization policies.

## Repository Structure

```text
k8s-rbac-model/
├── k8s-rbac-model_README.md
├── outputs/
│   ├── rbac_inventory_<timestamp>/
│   ├── authentication_authorization_inventory_<timestamp>/
│   ├── keystone_policy_model_<timestamp>/
│   └── keystone_permission_summary_<timestamp>/
└── scripts/
    ├── 01_rbac_inventory.sh
    ├── 02_authentication_authorization_inventory.sh
    ├── 03_keystone_policy_model_inventory.sh
    └── 04_keystone_permission_summary.sh
```

Generated output directories should remain excluded from Git because they may
contain internal usernames, groups, ServiceAccount names, project identifiers,
internal endpoints, infrastructure details, and authorization policies.

## Scripts

### `01_rbac_inventory.sh`

Collects the baseline Kubernetes RBAC inventory.

Main outputs include:

- current context and identity;
- visible namespaces;
- Roles and ClusterRoles;
- RoleBindings and ClusterRoleBindings;
- current effective permissions;
- common support permission checks;
- bindings to highly privileged roles;
- ServiceAccounts referenced by RBAC bindings.

The script does not retrieve Secret values, ServiceAccount tokens, client
certificates, or kubeconfig credentials.

### `02_authentication_authorization_inventory.sh`

Collects information about the cluster authentication and authorization
architecture.

Main outputs include:

- current identity and effective permissions;
- API server authentication and authorization flags;
- impersonation capability;
- external authentication webhook workload information;
- related ConfigMap names and keys;
- User and Group subjects referenced by Kubernetes RBAC.

### `03_keystone_policy_model_inventory.sh`

Collects the Kubernetes and OpenStack Keystone integration model when that
integration is present.

Main outputs include:

- API server container configuration;
- webhook-related API server flags;
- authentication webhook workload configuration;
- redacted external authorization policies;
- redacted synchronization configuration;
- related ServiceAccount and RBAC configuration.

Potential password, token, credential, and private-key values are redacted.
Authorization rules and internal infrastructure information must still be
handled as operationally sensitive data.

### `04_keystone_permission_summary.sh`

Produces a readable summary of external authorization policies while masking
project identifiers.

It identifies:

- matching external roles;
- project scope;
- Kubernetes resource permissions;
- non-resource permissions;
- unrestricted and restricted policies.

## Running the Inventory

Run the scripts from the repository root:

```bash
./k8s-rbac-model/scripts/01_rbac_inventory.sh
./k8s-rbac-model/scripts/02_authentication_authorization_inventory.sh
./k8s-rbac-model/scripts/03_keystone_policy_model_inventory.sh
./k8s-rbac-model/scripts/04_keystone_permission_summary.sh
```

Validate shell syntax before execution:

```bash
bash -n k8s-rbac-model/scripts/01_rbac_inventory.sh
bash -n k8s-rbac-model/scripts/02_authentication_authorization_inventory.sh
bash -n k8s-rbac-model/scripts/03_keystone_policy_model_inventory.sh
bash -n k8s-rbac-model/scripts/04_keystone_permission_summary.sh
```

All scripts are read-only from a Kubernetes resource-management perspective.

## Interpreting the Results

The generated inventory can be used to review:

- which identities receive namespace-scoped or cluster-scoped permissions;
- whether workloads use dedicated ServiceAccounts;
- whether bindings grant broader access than required;
- whether multiple bindings grant the same effective permissions;
- whether external authorization policies overlap with Kubernetes RBAC;
- whether support activities can be performed with reduced privileges.

The inventory output should be treated as evidence for a separate access review.
It must not be used as an automatic remediation input.

## Security Handling

Do not commit raw inventory output unless it has been reviewed and sanitized.

In particular, check outputs for:

- internal usernames and groups;
- ServiceAccount and workload names;
- project, tenant, or domain identifiers;
- internal registry and identity-provider endpoints;
- cluster, node, namespace, and context names;
- node names and IP addresses;
- API server flags and mounted host paths;
- authorization policy details;
- certificate and key file locations.

Never store the following in this module:

- kubeconfig credentials;
- bearer tokens;
- ServiceAccount tokens;
- client private keys;
- API server private keys;
- Secret values;
- unredacted passwords or application credentials.

## Operational Guidance

Any RBAC or external authorization change should be implemented separately from
the inventory workflow.

Before changing access:

1. Review the collected evidence.
2. Define the minimum required permissions.
3. Test the proposed role with a dedicated test identity.
4. Validate application and support workflows.
5. Prepare a rollback procedure.
6. Apply the change through the normal review process.
7. Re-run the inventory to confirm the resulting permissions.

## Limitations

The scripts report permissions visible to the executing identity. Results may be
incomplete when that identity cannot list cluster-scoped RBAC resources or read
the relevant authentication and authorization configuration.

Effective access may also depend on:

- external identity-provider configuration;
- admission controllers;
- namespace policies;
- workload security settings;
- infrastructure-level access outside Kubernetes.

The collected output should therefore be reviewed together with the broader
platform security model.
