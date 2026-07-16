# Kubernetes Namespace Onboarding

Reusable templates and example manifests for requesting, reviewing, and provisioning Kubernetes namespaces.

The purpose of this toolset is to standardize namespace onboarding and ensure that application teams provide the minimum technical, operational, security, and ownership information required before workloads are deployed.

## Structure

```text
k8s-namespace-onboarding/
├── k8s-namespace-onboarding_README.md
├── templates/
│   ├── namespace-onboarding-template.md
│   └── namespace-readiness-checklist.md
├── examples/
│   └── example-namespace-onboarding.md
└── manifests/
    ├── namespace.yaml
    ├── resource-quota.yaml
    ├── limit-range.yaml
    ├── service-account.yaml
    └── role-binding.yaml
```

## Files

### `templates/namespace-onboarding-template.md`

Main onboarding request template.

It collects information about:

* namespace ownership
* environment and criticality
* planned workloads
* CPU and memory requirements
* storage requirements
* RBAC and service accounts
* secrets and configuration
* networking and service exposure
* deployment model
* monitoring and logging
* recovery and security
* support responsibilities

### `templates/namespace-readiness-checklist.md`

Checklist for validating that the onboarding request is complete and that the namespace is ready for provisioning and workload deployment.

It can be used by application, platform, security, and operations teams during the onboarding review.

### `examples/example-namespace-onboarding.md`

Completed example for a fictional application.

The example demonstrates the expected level of detail without containing real organizational, infrastructure, repository, contact, or application information.

### `manifests/`

Example Kubernetes resources that can be adapted during namespace provisioning:

* `namespace.yaml` — namespace metadata, ownership labels, and annotations
* `resource-quota.yaml` — namespace-level resource limits
* `limit-range.yaml` — default and allowed container resource values
* `service-account.yaml` — workload or automation identity
* `role-binding.yaml` — namespace-scoped RBAC assignment

The manifests are examples and should not be applied without review.

## Recommended Workflow

1. Copy `templates/namespace-onboarding-template.md`.
2. Complete all mandatory sections.
3. Review the request using `templates/namespace-readiness-checklist.md`.
4. Resolve missing information, unsupported requirements, and security exceptions.
5. Adapt the example manifests to the approved namespace configuration.
6. Validate the manifests before applying them.
7. Provision the namespace and baseline resources.
8. Perform the post-onboarding checks.
9. Record the approval and any remaining actions.

## Manifest Customization

Replace all placeholders before using the manifests, including:

```text
<namespace-name>
<application-name>
<team-name>
<technical-owner>
<support-contact>
<ticket-reference>
<service-account-name>
<role-binding-name>
```

Review and adjust:

* namespace labels and annotations
* CPU and memory quotas
* Pod, Service, Secret, and ConfigMap limits
* storage limits
* default container requests and limits
* service-account token mounting
* RBAC permissions

The example quota and limit values are not platform defaults.

## Validation

The manifests can be validated locally after replacing their placeholders:

```bash
kubectl apply --dry-run=client -f manifests/namespace.yaml
kubectl apply --dry-run=client -f manifests/resource-quota.yaml
kubectl apply --dry-run=client -f manifests/limit-range.yaml
kubectl apply --dry-run=client -f manifests/service-account.yaml
kubectl apply --dry-run=client -f manifests/role-binding.yaml
```

All files can also be checked together:

```bash
kubectl apply --dry-run=client -f manifests/
```

To inspect the generated resources without applying them:

```bash
kubectl apply --dry-run=client -f manifests/ -o yaml
```

## Security Notes

* Do not store passwords, tokens, private keys, or certificates in onboarding documents.
* Avoid privileged containers, HostPath volumes, host networking, and cluster-wide RBAC unless explicitly reviewed.
* Use namespace-scoped permissions and least-privilege access.
* Keep `automountServiceAccountToken` disabled unless the workload requires Kubernetes API access.
* Use approved secret-management and container-image sources.
* Document and review all security exceptions.

## Responsibilities

### Application team

The application team provides:

* workload requirements
* resource estimates
* application manifests
* network and storage dependencies
* secrets and configuration requirements
* monitoring and alerting requirements
* support and recovery documentation

### Platform team

The platform team provides:

* namespace provisioning
* approved quotas and limits
* namespace-level RBAC
* supported ingress and storage integration
* platform monitoring and logging integration
* validation against platform capabilities
* review of elevated access and security exceptions

## Important

This toolset provides a reusable onboarding baseline. It does not replace platform-specific policies, security reviews, capacity checks, or change-management procedures.

