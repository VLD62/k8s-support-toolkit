# Kubernetes Namespace Readiness Checklist

Use this checklist before approving and provisioning a new Kubernetes namespace.

The checklist helps verify that the application team has provided the required information and that the requested namespace can be supported by the current Kubernetes platform.

---

## 1. Request and Ownership

* [ ] Namespace onboarding request is available.
* [ ] Requested namespace name is defined.
* [ ] Namespace name follows the agreed naming convention.
* [ ] Target environment is identified.
* [ ] Application or service name is documented.
* [ ] Business owner is identified.
* [ ] Technical owner is identified.
* [ ] Primary support team is identified.
* [ ] Escalation contact is available.
* [ ] Related project or ticket is referenced.

## 2. Namespace Classification

* [ ] Environment is classified as development, test, staging, or production.
* [ ] Business criticality is defined.
* [ ] Data classification is defined.
* [ ] Namespace lifetime is defined.
* [ ] Temporary namespaces have a planned removal date.
* [ ] Production support expectations are documented.

## 3. Workload Definition

* [ ] Planned Kubernetes workloads are listed.
* [ ] Workload types are defined.
* [ ] Expected replica counts are defined.
* [ ] High availability requirements are documented.
* [ ] Autoscaling requirements are documented.
* [ ] Scheduled Jobs and CronJobs are documented.
* [ ] Stateful workloads are clearly identified.
* [ ] Workload dependencies are documented.

## 4. Resource Management

* [ ] CPU requests are defined.
* [ ] CPU limits are defined.
* [ ] Memory requests are defined.
* [ ] Memory limits are defined.
* [ ] Expected workload growth is documented.
* [ ] Namespace ResourceQuota requirements are defined.
* [ ] Namespace LimitRange requirements are defined.
* [ ] Maximum expected Pod count is estimated.
* [ ] Requested resources are compatible with current cluster capacity.
* [ ] Resource values use valid Kubernetes quantity formats.

## 5. Storage

* [ ] Persistent storage requirements are documented.
* [ ] Required PersistentVolumeClaims are listed.
* [ ] Requested storage capacity is defined.
* [ ] StorageClass requirements are defined.
* [ ] Requested StorageClass is available on the platform.
* [ ] Access modes are compatible with the selected storage solution.
* [ ] Data retention requirements are documented.
* [ ] Backup requirements are documented.
* [ ] Restore requirements are documented.
* [ ] Stateful workload recovery procedures are available or planned.

## 6. Access and RBAC

* [ ] Required users and groups are identified.
* [ ] Required service accounts are identified.
* [ ] Requested namespace roles are documented.
* [ ] RoleBindings are defined.
* [ ] Least-privilege access has been applied.
* [ ] Namespace administrator access is justified.
* [ ] Cluster-wide permissions are not requested unless required.
* [ ] Any required ClusterRoleBinding has been reviewed.
* [ ] Automation and CI/CD identities are documented.
* [ ] Access ownership and removal procedures are defined.

## 7. Secrets and Configuration

* [ ] Required ConfigMaps are documented.
* [ ] Required Secrets are documented.
* [ ] Secret values are not included in the onboarding request.
* [ ] Secret ownership is defined.
* [ ] Secret rotation expectations are documented.
* [ ] External secret management requirements are documented.
* [ ] Certificates and private keys have an approved storage method.
* [ ] Environment-specific configuration is separated appropriately.
* [ ] Sensitive configuration is not stored in source control.

## 8. Networking

* [ ] Internal service dependencies are documented.
* [ ] Cross-namespace communication is documented.
* [ ] External outbound dependencies are documented.
* [ ] External inbound connectivity is documented.
* [ ] Required ports and protocols are listed.
* [ ] DNS dependencies are documented.
* [ ] NetworkPolicy requirements are documented.
* [ ] Default ingress and egress policies are understood.
* [ ] Firewall or proxy requirements are documented.
* [ ] External systems have confirmed connectivity requirements.

## 9. Services and Ingress

* [ ] Required Kubernetes Services are listed.
* [ ] Service types are defined.
* [ ] External exposure requirements are documented.
* [ ] Ingress requirements are documented.
* [ ] Requested hostnames are defined.
* [ ] URL paths are defined.
* [ ] TLS requirements are documented.
* [ ] Certificate ownership and provisioning are defined.
* [ ] DNS registration ownership is defined.
* [ ] Backend service ports match workload container ports.
* [ ] Health check paths are documented.
* [ ] Requested exposure model is supported by the platform.

## 10. Deployment Model

* [ ] Deployment method is defined.
* [ ] Source repository is documented.
* [ ] Manifest or Helm chart location is documented.
* [ ] Container registry location is documented.
* [ ] Approved image registry is used.
* [ ] Argo CD integration requirements are documented.
* [ ] Argo CD project is defined or planned.
* [ ] Synchronization policy is defined.
* [ ] Automated pruning expectations are defined.
* [ ] Self-healing expectations are defined.
* [ ] Deployment approval responsibilities are defined.
* [ ] Rollback procedure is documented.

## 11. Monitoring and Logging

* [ ] Application metrics requirements are documented.
* [ ] Prometheus scraping requirements are documented.
* [ ] Metrics endpoints are available.
* [ ] Application logs are written to standard output and standard error.
* [ ] Centralized logging requirements are documented.
* [ ] Required dashboards are documented.
* [ ] Required alerts are documented.
* [ ] Alert thresholds are defined.
* [ ] Alert severity levels are defined.
* [ ] Alert recipients are defined.
* [ ] Application health endpoints are documented.
* [ ] Operational visibility is sufficient for support teams.

## 12. Availability and Recovery

* [ ] Availability expectations are documented.
* [ ] Required replica counts are defined.
* [ ] Pod disruption requirements are documented.
* [ ] Recovery Time Objective is defined where applicable.
* [ ] Recovery Point Objective is defined where applicable.
* [ ] Backup ownership is defined.
* [ ] Restore responsibility is defined.
* [ ] Disaster recovery requirements are documented.
* [ ] Recovery documentation is available or planned.
* [ ] Critical workloads have a tested recovery approach.

## 13. Security

* [ ] Containers are configured to run as non-root where possible.
* [ ] Privileged containers are not used unless approved.
* [ ] Host networking is not used unless approved.
* [ ] HostPath volumes are not used unless approved.
* [ ] Linux capabilities are minimized.
* [ ] Read-only root filesystem is used where applicable.
* [ ] Container image scanning is enabled.
* [ ] Known critical vulnerabilities have been addressed.
* [ ] Images use approved base images where required.
* [ ] Pod security requirements are documented.
* [ ] Elevated permissions have a technical justification.
* [ ] Security exceptions have an owner and expiration date.
* [ ] Sensitive data exposure has been reviewed.

## 14. Operational Support

* [ ] Primary support team is defined.
* [ ] Secondary support team is defined where applicable.
* [ ] Support hours are documented.
* [ ] Escalation path is documented.
* [ ] Operational runbook is available or planned.
* [ ] Troubleshooting documentation is available or planned.
* [ ] Known limitations are documented.
* [ ] Common failure scenarios are documented.
* [ ] Maintenance responsibilities are defined.
* [ ] Decommissioning responsibility is defined.

## 15. Platform Validation

* [ ] Requested Kubernetes features are supported.
* [ ] Requested API versions are supported.
* [ ] Requested StorageClass is supported.
* [ ] Requested Ingress configuration is supported.
* [ ] Requested deployment model is supported.
* [ ] Requested RBAC model is acceptable.
* [ ] Requested resource quota is acceptable.
* [ ] Requested network connectivity is feasible.
* [ ] Required platform integrations are available.
* [ ] No unsupported cluster-level changes are required.
* [ ] Open risks and exceptions are documented.

## 16. Provisioning Validation

Complete after the namespace and baseline resources have been created.

* [ ] Namespace exists.
* [ ] Required labels are applied.
* [ ] Required annotations are applied.
* [ ] ResourceQuota is created.
* [ ] LimitRange is created.
* [ ] Required service accounts are created.
* [ ] Required Roles are created.
* [ ] Required RoleBindings are created.
* [ ] Default network policies are applied where required.
* [ ] Required secrets integration is available.
* [ ] Monitoring integration is validated.
* [ ] Logging integration is validated.
* [ ] Ingress integration is validated where applicable.
* [ ] Storage provisioning is validated where applicable.
* [ ] Argo CD deployment access is validated where applicable.

## 17. Post-Onboarding Validation

* [ ] Application workloads deploy successfully.
* [ ] Pods become Ready.
* [ ] Resource requests and limits are visible.
* [ ] PersistentVolumeClaims bind successfully.
* [ ] Internal service communication works.
* [ ] External dependencies are reachable.
* [ ] Ingress routing works.
* [ ] DNS resolution works.
* [ ] TLS certificate is valid.
* [ ] Application metrics are collected.
* [ ] Application logs are available.
* [ ] Alerts are configured.
* [ ] Application team confirms operational readiness.
* [ ] Support team confirms documentation availability.

## 18. Final Approval

| Review area           | Reviewer | Status                                 | Date           | Notes     |
| --------------------- | -------- | -------------------------------------- | -------------- | --------- |
| Application readiness | `<name>` | `<approved / pending / rejected>`      | `<YYYY-MM-DD>` | `<notes>` |
| Platform readiness    | `<name>` | `<approved / pending / rejected>`      | `<YYYY-MM-DD>` | `<notes>` |
| Security review       | `<name>` | `<approved / not required / rejected>` | `<YYYY-MM-DD>` | `<notes>` |
| Operations readiness  | `<name>` | `<approved / pending / rejected>`      | `<YYYY-MM-DD>` | `<notes>` |

## 19. Outstanding Actions

| Action     | Owner     | Due date       | Status                             |
| ---------- | --------- | -------------- | ---------------------------------- |
| `<action>` | `<owner>` | `<YYYY-MM-DD>` | `<open / in progress / completed>` |

## 20. Final Status

* [ ] Approved for namespace provisioning
* [ ] Approved with documented actions
* [ ] Pending additional information
* [ ] Rejected

Final notes:

`<Document the approval decision, remaining risks, exceptions, and follow-up actions.>`

