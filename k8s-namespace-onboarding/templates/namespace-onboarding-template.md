# Kubernetes Namespace Onboarding Request

Use this template when requesting a new Kubernetes namespace for an application, service, team, or project.

Complete all mandatory sections before submitting the request. Sections marked as optional may be omitted when they are not applicable.

---

## 1. Request Information

| Field                     | Value                                         |
| ------------------------- | --------------------------------------------- |
| Request date              | `<YYYY-MM-DD>`                                |
| Requested by              | `<name or team>`                              |
| Requested namespace       | `<namespace-name>`                            |
| Environment               | `<development / test / staging / production>` |
| Required completion date  | `<YYYY-MM-DD or not applicable>`              |
| Related ticket or project | `<reference or not applicable>`               |

## 2. Application Information

| Field                       | Value                                     |
| --------------------------- | ----------------------------------------- |
| Application or service name | `<name>`                                  |
| Short description           | `<purpose of the application>`            |
| Business owner              | `<name or team>`                          |
| Technical owner             | `<name or team>`                          |
| Support contact             | `<team, email, or communication channel>` |
| Source code repository      | `<repository URL or not applicable>`      |
| Documentation               | `<documentation URL or not applicable>`   |

## 3. Namespace Classification

| Field                     | Value                                             |
| ------------------------- | ------------------------------------------------- |
| Environment type          | `<development / test / staging / production>`     |
| Business criticality      | `<low / medium / high / critical>`                |
| Data classification       | `<public / internal / confidential / restricted>` |
| Expected lifetime         | `<temporary / long-running>`                      |
| Planned decommission date | `<YYYY-MM-DD or not applicable>`                  |

## 4. Workload Overview

Describe the workloads that will run in the namespace.

| Workload          | Kubernetes type                              |   Replicas | Description |
| ----------------- | -------------------------------------------- | ---------: | ----------- |
| `<workload-name>` | `<Deployment / StatefulSet / CronJob / Job>` | `<number>` | `<purpose>` |

Additional information:

* Container image registry: `<registry location>`
* Expected deployment frequency: `<frequency>`
* Horizontal autoscaling required: `<yes / no>`
* High availability required: `<yes / no>`
* Pod disruption requirements: `<description or not applicable>`

## 5. Resource Requirements

Provide estimated resource requirements per workload.

| Workload          | CPU request | CPU limit | Memory request | Memory limit |
| ----------------- | ----------: | --------: | -------------: | -----------: |
| `<workload-name>` |   `<value>` | `<value>` |      `<value>` |    `<value>` |

Requested namespace quota:

| Resource                                 | Requested quota |
| ---------------------------------------- | --------------: |
| CPU requests                             |       `<value>` |
| CPU limits                               |       `<value>` |
| Memory requests                          |       `<value>` |
| Memory limits                            |       `<value>` |
| Maximum number of Pods                   |       `<value>` |
| Maximum number of Services               |       `<value>` |
| Maximum number of PersistentVolumeClaims |       `<value>` |

Expected workload growth:

`<Describe expected changes in workload size or resource usage.>`

## 6. Storage Requirements

| Field                       | Value                                            |
| --------------------------- | ------------------------------------------------ |
| Persistent storage required | `<yes / no>`                                     |
| Storage class               | `<storage-class or to be determined>`            |
| Requested capacity          | `<size>`                                         |
| Access mode                 | `<ReadWriteOnce / ReadWriteMany / ReadOnlyMany>` |
| Data retention period       | `<period>`                                       |
| Backup required             | `<yes / no>`                                     |
| Restore procedure required  | `<yes / no>`                                     |

List the required volumes:

| PVC name     | Capacity | Storage class     | Access mode | Purpose         |
| ------------ | -------: | ----------------- | ----------- | --------------- |
| `<pvc-name>` | `<size>` | `<storage-class>` | `<mode>`    | `<description>` |

## 7. Access and RBAC

List all users, groups, or automation accounts requiring access.

| User, group, or service account | Required access                  | Reason     |
| ------------------------------- | -------------------------------- | ---------- |
| `<identity>`                    | `<view / edit / admin / custom>` | `<reason>` |

Service accounts required:

| Service account          | Used by      | Required permissions |
| ------------------------ | ------------ | -------------------- |
| `<service-account-name>` | `<workload>` | `<permissions>`      |

Additional RBAC requirements:

`<Describe custom Roles, RoleBindings, or ClusterRole access.>`

Cluster-wide permissions should be avoided unless they are explicitly required and reviewed.

## 8. Secrets and Configuration

| Field                               | Value        |
| ----------------------------------- | ------------ |
| Kubernetes ConfigMaps required      | `<yes / no>` |
| Kubernetes Secrets required         | `<yes / no>` |
| External secret management required | `<yes / no>` |
| Secret owner                        | `<team>`     |
| Secret rotation required            | `<yes / no>` |

List the required configuration and secrets without including actual secret values:

| Name     | Type                                     | Used by      | Description     |
| -------- | ---------------------------------------- | ------------ | --------------- |
| `<name>` | `<ConfigMap / Secret / external secret>` | `<workload>` | `<description>` |

Actual passwords, tokens, certificates, and private keys must not be included in this document.

## 9. Networking and Dependencies

### Internal connectivity

| Source workload | Destination              | Port and protocol | Purpose     |
| --------------- | ------------------------ | ----------------- | ----------- |
| `<source>`      | `<service or namespace>` | `<port/protocol>` | `<purpose>` |

### External connectivity

| Direction              | External system | Address or DNS name | Port and protocol | Purpose     |
| ---------------------- | --------------- | ------------------- | ----------------- | ----------- |
| `<inbound / outbound>` | `<system>`      | `<address>`         | `<port/protocol>` | `<purpose>` |

NetworkPolicy requirements:

`<Describe required ingress and egress rules or state that default policies are sufficient.>`

## 10. Service Exposure

| Field                       | Value                                                           |
| --------------------------- | --------------------------------------------------------------- |
| Kubernetes Service required | `<yes / no>`                                                    |
| Service type                | `<ClusterIP / NodePort / LoadBalancer>`                         |
| External access required    | `<yes / no>`                                                    |
| Ingress required            | `<yes / no>`                                                    |
| Requested hostname          | `<hostname or not applicable>`                                  |
| URL path                    | `<path or not applicable>`                                      |
| TLS required                | `<yes / no>`                                                    |
| Certificate source          | `<certificate manager / provided certificate / not applicable>` |

Required exposed endpoints:

| Service          |     Port | Protocol               | Hostname or path  | Exposure                |
| ---------------- | -------: | ---------------------- | ----------------- | ----------------------- |
| `<service-name>` | `<port>` | `<HTTP / HTTPS / TCP>` | `<hostname/path>` | `<internal / external>` |

## 11. Deployment and Delivery

| Field                        | Value                                              |
| ---------------------------- | -------------------------------------------------- |
| Deployment method            | `<Argo CD / Helm / kubectl / CI pipeline / other>` |
| Deployment repository        | `<repository URL>`                                 |
| Manifest location            | `<repository path>`                                |
| Helm chart used              | `<yes / no>`                                       |
| Argo CD application required | `<yes / no>`                                       |
| Argo CD project              | `<project or to be determined>`                    |
| Automated synchronization    | `<yes / no>`                                       |
| Automated pruning            | `<yes / no>`                                       |
| Self-healing                 | `<yes / no>`                                       |

Deployment responsibilities:

| Activity                       | Responsible team |
| ------------------------------ | ---------------- |
| Application manifests          | `<team>`         |
| Container images               | `<team>`         |
| Deployment pipeline            | `<team>`         |
| Namespace configuration        | `<team>`         |
| Production deployment approval | `<team>`         |

## 12. Monitoring, Logging, and Alerting

| Field                        | Value                       |
| ---------------------------- | --------------------------- |
| Metrics required             | `<yes / no>`                |
| Prometheus scraping required | `<yes / no>`                |
| Dashboards required          | `<yes / no>`                |
| Centralized logging required | `<yes / no>`                |
| Alerting required            | `<yes / no>`                |
| Alert recipient              | `<team or channel>`         |
| Health endpoints             | `<paths or not applicable>` |

Required alerts:

| Alert          | Condition     | Severity               | Recipient |
| -------------- | ------------- | ---------------------- | --------- |
| `<alert-name>` | `<condition>` | `<warning / critical>` | `<team>`  |

Application logs should be written to standard output and standard error unless another approved logging model is required.

## 13. Availability and Recovery

| Field                             | Value                                   |
| --------------------------------- | --------------------------------------- |
| Availability requirement          | `<best effort / business hours / 24x7>` |
| Recovery Time Objective           | `<duration or not defined>`             |
| Recovery Point Objective          | `<duration or not defined>`             |
| Backup required                   | `<yes / no>`                            |
| Disaster recovery required        | `<yes / no>`                            |
| Multi-replica deployment required | `<yes / no>`                            |

Recovery documentation:

`<Link to the recovery procedure or explain how the application will be restored.>`

## 14. Security Requirements

| Requirement                    | Value                            |
| ------------------------------ | -------------------------------- |
| Containers run as non-root     | `<yes / no / not yet validated>` |
| Read-only root filesystem      | `<yes / no / not applicable>`    |
| Privileged containers required | `<yes / no>`                     |
| Host networking required       | `<yes / no>`                     |
| HostPath volumes required      | `<yes / no>`                     |
| Image vulnerability scanning   | `<enabled / not enabled>`        |
| Approved image registry used   | `<yes / no>`                     |
| Pod security requirements      | `<description>`                  |

Any requirement for privileged containers, host access, or elevated permissions must include a technical justification.

Technical justification:

`<Provide justification or state not applicable.>`

## 15. Support and Operations

| Field                         | Value                             |
| ----------------------------- | --------------------------------- |
| Primary support team          | `<team>`                          |
| Secondary support team        | `<team or not applicable>`        |
| Support hours                 | `<business hours / 24x7 / other>` |
| Escalation contact            | `<contact>`                       |
| Operational runbook           | `<URL or not yet available>`      |
| Troubleshooting documentation | `<URL or not yet available>`      |
| Known limitations             | `<description or none>`           |

## 16. Ownership Responsibilities

### Application team

The application team is responsible for:

* application source code and container images
* Kubernetes workload manifests
* resource estimates and workload configuration
* application-level monitoring and alerts
* application secrets and configuration requirements
* application documentation and operational runbooks
* vulnerability remediation in application images
* identifying required network and storage dependencies

### Platform team

The platform team is responsible for:

* namespace creation
* approved namespace-level quotas and limits
* namespace-level access configuration
* platform ingress and storage integration
* platform monitoring and logging capabilities
* cluster-level security controls
* review of elevated access requirements
* validation against supported Kubernetes platform capabilities

## 17. Readiness Confirmation

Confirm the following before onboarding is approved:

* [ ] Namespace name follows the agreed naming convention.
* [ ] Application and technical owners are identified.
* [ ] Environment and business criticality are defined.
* [ ] Workloads and deployment model are documented.
* [ ] CPU and memory requests and limits are provided.
* [ ] Namespace quota requirements are defined.
* [ ] Storage requirements are documented.
* [ ] RBAC and service account requirements are documented.
* [ ] Secrets and configuration requirements are documented.
* [ ] Internal and external network dependencies are documented.
* [ ] Service, Ingress, DNS, and TLS requirements are documented.
* [ ] Deployment ownership and repository locations are defined.
* [ ] Monitoring, logging, and alerting requirements are defined.
* [ ] Backup and recovery requirements are reviewed.
* [ ] Security requirements are reviewed.
* [ ] Support ownership and escalation contacts are defined.
* [ ] Operational documentation is available or planned.

## 18. Approval

| Role                             | Name     | Decision                               | Date           |
| -------------------------------- | -------- | -------------------------------------- | -------------- |
| Application owner                | `<name>` | `<approved / rejected>`                | `<YYYY-MM-DD>` |
| Technical owner                  | `<name>` | `<approved / rejected>`                | `<YYYY-MM-DD>` |
| Platform reviewer                | `<name>` | `<approved / rejected>`                | `<YYYY-MM-DD>` |
| Security reviewer, when required | `<name>` | `<approved / rejected / not required>` | `<YYYY-MM-DD>` |

## 19. Additional Notes

`<Add any additional information, assumptions, exceptions, or unresolved topics.>`

