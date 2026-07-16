# Example Kubernetes Namespace Onboarding Request

This document demonstrates how the namespace onboarding template can be completed for a fictional application.

All names, repositories, domains, addresses, and contacts in this example are placeholders.

---

## 1. Request Information

| Field                     | Value                      |
| ------------------------- | -------------------------- |
| Request date              | `2026-07-16`               |
| Requested by              | `Example Application Team` |
| Requested namespace       | `example-orders-test`      |
| Environment               | `test`                     |
| Required completion date  | `2026-07-31`               |
| Related ticket or project | `PLATFORM-1234`            |

## 2. Application Information

| Field                       | Value                                                   |
| --------------------------- | ------------------------------------------------------- |
| Application or service name | `Example Orders Service`                                |
| Short description           | `REST service for creating and retrieving test orders.` |
| Business owner              | `Example Product Team`                                  |
| Technical owner             | `Example Application Team`                              |
| Support contact             | `example-app-support@example.com`                       |
| Source code repository      | `https://git.example.com/example/orders-service`        |
| Documentation               | `https://docs.example.com/orders-service`               |

## 3. Namespace Classification

| Field                     | Value            |
| ------------------------- | ---------------- |
| Environment type          | `test`           |
| Business criticality      | `medium`         |
| Data classification       | `internal`       |
| Expected lifetime         | `long-running`   |
| Planned decommission date | `not applicable` |

The namespace is intended for integration and acceptance testing. It does not process production customer data.

## 4. Workload Overview

| Workload         | Kubernetes type | Replicas | Description                             |
| ---------------- | --------------- | -------: | --------------------------------------- |
| `orders-api`     | `Deployment`    |      `2` | Exposes the application REST API.       |
| `orders-worker`  | `Deployment`    |      `1` | Processes asynchronous order events.    |
| `orders-cleanup` | `CronJob`       |      `1` | Removes expired test data once per day. |

Additional information:

* Container image registry: `registry.example.com/example/orders-service`
* Expected deployment frequency: `two to five deployments per week`
* Horizontal autoscaling required: `no`
* High availability required: `limited; two API replicas`
* Pod disruption requirements: `at least one orders-api replica should remain available`

## 5. Resource Requirements

| Workload         | CPU request | CPU limit | Memory request | Memory limit |
| ---------------- | ----------: | --------: | -------------: | -----------: |
| `orders-api`     |      `250m` |       `1` |        `512Mi` |        `1Gi` |
| `orders-worker`  |      `200m` |    `500m` |        `256Mi` |      `512Mi` |
| `orders-cleanup` |      `100m` |    `250m` |        `128Mi` |      `256Mi` |

Requested namespace quota:

| Resource                                 | Requested quota |
| ---------------------------------------- | --------------: |
| CPU requests                             |             `2` |
| CPU limits                               |             `4` |
| Memory requests                          |           `4Gi` |
| Memory limits                            |           `8Gi` |
| Maximum number of Pods                   |            `15` |
| Maximum number of Services               |             `5` |
| Maximum number of PersistentVolumeClaims |             `2` |

Expected workload growth:

The namespace may receive one additional worker replica and one additional test utility workload during the next six months. The requested quota includes capacity for this expected growth.

## 6. Storage Requirements

| Field                       | Value                    |
| --------------------------- | ------------------------ |
| Persistent storage required | `yes`                    |
| Storage class               | `standard-block-storage` |
| Requested capacity          | `20Gi`                   |
| Access mode                 | `ReadWriteOnce`          |
| Data retention period       | `30 days`                |
| Backup required             | `no`                     |
| Restore procedure required  | `no`                     |

Required volumes:

| PVC name           | Capacity | Storage class            | Access mode     | Purpose                                 |
| ------------------ | -------: | ------------------------ | --------------- | --------------------------------------- |
| `orders-test-data` |   `20Gi` | `standard-block-storage` | `ReadWriteOnce` | Stores temporary integration-test data. |

The stored data can be recreated from test fixtures, so platform-level backup is not required.

## 7. Access and RBAC

| User, group, or service account | Required access | Reason                                                             |
| ------------------------------- | --------------- | ------------------------------------------------------------------ |
| `example-orders-developers`     | `view`          | Allows developers to inspect workloads, logs, and events.          |
| `example-orders-operators`      | `edit`          | Allows the support team to restart and manage namespace workloads. |
| `orders-deployer`               | `custom`        | Used by the deployment process to manage application resources.    |

Service accounts required:

| Service account   | Used by                       | Required permissions                                  |
| ----------------- | ----------------------------- | ----------------------------------------------------- |
| `orders-runtime`  | `orders-api`, `orders-worker` | No Kubernetes API access required.                    |
| `orders-deployer` | Deployment automation         | Manage supported workload resources in the namespace. |

Additional RBAC requirements:

The deployment service account requires namespace-scoped access to Deployments, StatefulSets, Jobs, CronJobs, Services, ConfigMaps, Secrets, and Ingress resources.

Cluster-wide access is not required.

## 8. Secrets and Configuration

| Field                               | Value                      |
| ----------------------------------- | -------------------------- |
| Kubernetes ConfigMaps required      | `yes`                      |
| Kubernetes Secrets required         | `yes`                      |
| External secret management required | `yes`                      |
| Secret owner                        | `Example Application Team` |
| Secret rotation required            | `yes`                      |

Required configuration and secrets:

| Name               | Type              | Used by                       | Description                              |
| ------------------ | ----------------- | ----------------------------- | ---------------------------------------- |
| `orders-config`    | `ConfigMap`       | `orders-api`, `orders-worker` | Non-sensitive application configuration. |
| `orders-database`  | `external secret` | `orders-api`, `orders-worker` | Test database credentials.               |
| `orders-api-token` | `external secret` | `orders-api`                  | Token used for an external test API.     |

Secret values are managed outside the Git repository and are not included in Kubernetes manifests.

Database credentials should be rotated every 90 days.

## 9. Networking and Dependencies

### Internal connectivity

| Source workload | Destination                 | Port and protocol | Purpose                                     |
| --------------- | --------------------------- | ----------------- | ------------------------------------------- |
| `orders-api`    | `orders-worker`             | `8081/TCP`        | Internal worker health and status endpoint. |
| `orders-api`    | `test-database.example.svc` | `5432/TCP`        | Test database connectivity.                 |

### External connectivity

| Direction  | External system     | Address or DNS name         | Port and protocol | Purpose                          |
| ---------- | ------------------- | --------------------------- | ----------------- | -------------------------------- |
| `outbound` | Test payment API    | `payments-test.example.com` | `443/TCP`         | Simulates payment authorization. |
| `outbound` | Test message broker | `broker-test.example.com`   | `9093/TCP`        | Publishes test order events.     |
| `inbound`  | Internal test users | `orders-test.example.com`   | `443/TCP`         | Access to the test REST API.     |

NetworkPolicy requirements:

* Allow traffic from the platform ingress controller to the `orders-api` Service.
* Allow `orders-api` and `orders-worker` to access the test database.
* Allow outbound HTTPS access to the test payment API.
* Allow outbound access to the test message broker.
* Deny all other inbound namespace traffic by default.

## 10. Service Exposure

| Field                       | Value                                    |
| --------------------------- | ---------------------------------------- |
| Kubernetes Service required | `yes`                                    |
| Service type                | `ClusterIP`                              |
| External access required    | `yes, internal organization access only` |
| Ingress required            | `yes`                                    |
| Requested hostname          | `orders-test.example.com`                |
| URL path                    | `/api`                                   |
| TLS required                | `yes`                                    |
| Certificate source          | `platform certificate manager`           |

Required exposed endpoints:

| Service      |   Port | Protocol                | Hostname or path              | Exposure   |
| ------------ | -----: | ----------------------- | ----------------------------- | ---------- |
| `orders-api` | `8080` | `HTTPS through Ingress` | `orders-test.example.com/api` | `internal` |

Direct NodePort or LoadBalancer exposure is not required.

## 11. Deployment and Delivery

| Field                        | Value                                               |
| ---------------------------- | --------------------------------------------------- |
| Deployment method            | `Argo CD and Helm`                                  |
| Deployment repository        | `https://git.example.com/example/orders-deployment` |
| Manifest location            | `environments/test/orders-service`                  |
| Helm chart used              | `yes`                                               |
| Argo CD application required | `yes`                                               |
| Argo CD project              | `example-test-applications`                         |
| Automated synchronization    | `yes`                                               |
| Automated pruning            | `yes`                                               |
| Self-healing                 | `yes`                                               |

Deployment responsibilities:

| Activity                 | Responsible team           |
| ------------------------ | -------------------------- |
| Application manifests    | `Example Application Team` |
| Container images         | `Example Application Team` |
| Deployment pipeline      | `Example Application Team` |
| Namespace configuration  | `Platform Team`            |
| Test deployment approval | `Example Application Team` |

The deployment repository must not contain plain-text credentials or private keys.

## 12. Monitoring, Logging, and Alerting

| Field                        | Value                                       |
| ---------------------------- | ------------------------------------------- |
| Metrics required             | `yes`                                       |
| Prometheus scraping required | `yes`                                       |
| Dashboards required          | `yes`                                       |
| Centralized logging required | `yes`                                       |
| Alerting required            | `yes`                                       |
| Alert recipient              | `example-app-support@example.com`           |
| Health endpoints             | `/health/live`, `/health/ready`, `/metrics` |

Required alerts:

| Alert                     | Condition                               | Severity   | Recipient                  |
| ------------------------- | --------------------------------------- | ---------- | -------------------------- |
| `OrdersApiUnavailable`    | No Ready API replicas for five minutes  | `critical` | `Example Application Team` |
| `OrdersApiHighErrorRate`  | HTTP 5xx rate above 10% for ten minutes | `warning`  | `Example Application Team` |
| `OrdersWorkerUnavailable` | Worker unavailable for ten minutes      | `warning`  | `Example Application Team` |
| `OrdersStorageUsageHigh`  | PVC usage above 85%                     | `warning`  | `Example Application Team` |

Application logs are written to standard output and standard error in structured JSON format.

## 13. Availability and Recovery

| Field                             | Value                          |
| --------------------------------- | ------------------------------ |
| Availability requirement          | `business hours`               |
| Recovery Time Objective           | `4 hours`                      |
| Recovery Point Objective          | `not applicable for test data` |
| Backup required                   | `no`                           |
| Disaster recovery required        | `no`                           |
| Multi-replica deployment required | `yes for orders-api`           |

Recovery documentation:

The application can be redeployed from Git through Argo CD. Test data can be recreated using the application test-data initialization Job.

## 14. Security Requirements

| Requirement                    | Value                               |
| ------------------------------ | ----------------------------------- |
| Containers run as non-root     | `yes`                               |
| Read-only root filesystem      | `yes for the API and worker`        |
| Privileged containers required | `no`                                |
| Host networking required       | `no`                                |
| HostPath volumes required      | `no`                                |
| Image vulnerability scanning   | `enabled`                           |
| Approved image registry used   | `yes`                               |
| Pod security requirements      | `restricted workload configuration` |

Technical justification:

No privileged access, host networking, HostPath storage, or additional Linux capabilities are required.

The application requires a writable temporary directory mounted through an `emptyDir` volume.

## 15. Support and Operations

| Field                         | Value                                                                             |
| ----------------------------- | --------------------------------------------------------------------------------- |
| Primary support team          | `Example Application Team`                                                        |
| Secondary support team        | `Platform Team for platform-related incidents`                                    |
| Support hours                 | `business hours`                                                                  |
| Escalation contact            | `example-app-support@example.com`                                                 |
| Operational runbook           | `https://docs.example.com/orders-service/runbook`                                 |
| Troubleshooting documentation | `https://docs.example.com/orders-service/troubleshooting`                         |
| Known limitations             | `The test payment system may be unavailable during external maintenance windows.` |

## 16. Ownership Responsibilities

### Application team

The Example Application Team is responsible for:

* application code and container images
* Helm values and workload manifests
* application secrets and configuration requirements
* application dashboards and alerts
* operational and troubleshooting documentation
* application vulnerability remediation
* deployment validation
* test data lifecycle

### Platform team

The Platform Team is responsible for:

* namespace provisioning
* namespace labels and annotations
* quota and limit configuration
* namespace-level RBAC integration
* ingress, storage, monitoring, and logging platform integration
* review of requested network and security controls
* validation against platform capabilities

## 17. Readiness Confirmation

* [x] Namespace name follows the agreed naming convention.
* [x] Application and technical owners are identified.
* [x] Environment and business criticality are defined.
* [x] Workloads and deployment model are documented.
* [x] CPU and memory requests and limits are provided.
* [x] Namespace quota requirements are defined.
* [x] Storage requirements are documented.
* [x] RBAC and service account requirements are documented.
* [x] Secrets and configuration requirements are documented.
* [x] Internal and external network dependencies are documented.
* [x] Service, Ingress, DNS, and TLS requirements are documented.
* [x] Deployment ownership and repository locations are defined.
* [x] Monitoring, logging, and alerting requirements are defined.
* [x] Backup and recovery requirements are reviewed.
* [x] Security requirements are reviewed.
* [x] Support ownership and escalation contacts are defined.
* [x] Operational documentation is available or planned.

## 18. Approval

| Role                             | Name                                | Decision                | Date         |
| -------------------------------- | ----------------------------------- | ----------------------- | ------------ |
| Application owner                | `Example Product Owner`             | `approved`              | `2026-07-17` |
| Technical owner                  | `Example Technical Lead`            | `approved`              | `2026-07-17` |
| Platform reviewer                | `Example Platform Engineer`         | `approved with actions` | `2026-07-18` |
| Security reviewer, when required | `not required for test environment` | `not required`          | `2026-07-18` |

## 19. Additional Notes

The following actions must be completed before the first deployment:

* Create the requested DNS record.
* Configure external secret integration.
* Validate access to the test database and message broker.
* Confirm that the selected StorageClass name matches the target cluster.
* Validate the Argo CD project and repository permissions.

