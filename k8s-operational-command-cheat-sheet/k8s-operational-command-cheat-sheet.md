# Kubernetes Operational Command Cheat Sheet

A practical command reference for day-to-day Kubernetes platform support, workload troubleshooting, access checks, storage review, Traefik routing, Helm releases, and Argo CD operations.

> **Scope:** Operational investigation and controlled support actions.  
> **Convention:** Replace values inside `<...>` with environment-specific names.  
> **Alias:** If `alias k=kubectl` is configured, `kubectl` can be replaced with `k`.

---

## 1. Operational Safety Rules

Before making any change:

```bash
kubectl config current-context
kubectl config view --minify
kubectl config get-contexts
```

Confirm the target namespace:

```bash
kubectl config view --minify --output 'jsonpath={..namespace}'; echo
```

Use server-side validation or a dry run where applicable:

```bash
kubectl apply --server-side --dry-run=server -f <manifest.yaml>
kubectl diff -f <manifest.yaml>
```

Export the current resource before changing it:

```bash
kubectl get <resource>/<name> -n <namespace> -o yaml \
  > <resource>-<name>-before-change.yaml
```

### Important cautions

- Prefer Git/Argo CD changes over direct production edits.
- Avoid `kubectl edit` for GitOps-managed resources unless performing an approved emergency action.
- Direct changes can be reverted automatically by Argo CD.
- `kubectl get all` does **not** return every Kubernetes resource type.
- Never print, copy, or store decoded Secret values in tickets or shared logs.
- Confirm PodDisruptionBudgets and workload redundancy before draining a node.
- Treat commands in the **Destructive Operations** section as high risk.

---

## 2. Client and Server Compatibility

Check the Kubernetes client and server versions before performing operational work:

```bash
kubectl version
kubectl version --client
```

Use a `kubectl` version supported by the target Kubernetes cluster and by the organization's platform policy.

Avoid storing cluster-specific information in this document, including:

- internal URLs and domain names
- cluster names and contexts
- IP addresses
- environment-specific StorageClass names
- usernames, account names, and namespaces
- credentials, tokens, certificates, and Secret values

---

## 3. Context and Namespace Management

List contexts:

```bash
kubectl config get-contexts
```

Show the active context:

```bash
kubectl config current-context
```

Switch context:

```bash
kubectl config use-context <context>
```

Set the default namespace for the current context:

```bash
kubectl config set-context --current --namespace=<namespace>
```

Temporarily override context or namespace:

```bash
kubectl --context=<context> get nodes
kubectl -n <namespace> get pods
```

Show cluster endpoints from kubeconfig:

```bash
kubectl config view --minify
```

List namespaces:

```bash
kubectl get namespaces
kubectl get ns --show-labels
```

---

## 4. API Discovery and Resource Inventory

List supported API resources:

```bash
kubectl api-resources
kubectl api-resources --namespaced=true
kubectl api-resources --namespaced=false
kubectl api-resources --verbs=list
```

List available API versions:

```bash
kubectl api-versions
```

Explain a resource or field:

```bash
kubectl explain deployment
kubectl explain deployment.spec
kubectl explain deployment.spec.template.spec.containers
kubectl explain ingress.spec
```

List common workload resources across all namespaces:

```bash
kubectl get deployments,statefulsets,daemonsets,jobs,cronjobs -A
```

List Pods, Services, Ingresses, PVCs, and ConfigMaps:

```bash
kubectl get pods,services,ingresses,pvc,configmaps -A
```

List custom resource definitions:

```bash
kubectl get crd
```

Search CRDs by name:

```bash
kubectl get crd | grep -Ei 'traefik|argoproj|monitoring|cert'
```

---

## 5. Fast Cluster Overview

Nodes:

```bash
kubectl get nodes -o wide
kubectl get nodes --show-labels
kubectl describe node <node>
```

Namespaces and workloads:

```bash
kubectl get ns
kubectl get pods -A -o wide
kubectl get deploy,statefulset,daemonset -A
```

Non-running Pods:

```bash
kubectl get pods -A --field-selector=status.phase!=Running
```

Pods not currently ready:

```bash
kubectl get pods -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,POD:.metadata.name,READY:.status.containerStatuses[*].ready,PHASE:.status.phase,NODE:.spec.nodeName'
```

Recent events:

```bash
kubectl get events -A --sort-by=.metadata.creationTimestamp
```

Warning events:

```bash
kubectl get events -A \
  --field-selector=type=Warning \
  --sort-by=.metadata.creationTimestamp
```

Resource usage, when Metrics Server is available:

```bash
kubectl top nodes
kubectl top pods -A
kubectl top pods -n <namespace> --containers
```

---

## 6. Workload Inspection

### Deployments

```bash
kubectl get deployment -n <namespace>
kubectl get deployment/<deployment> -n <namespace> -o wide
kubectl describe deployment/<deployment> -n <namespace>
kubectl get deployment/<deployment> -n <namespace> -o yaml
```

Show image names:

```bash
kubectl get deployment/<deployment> -n <namespace> \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name}{" -> "}{.image}{"\n"}{end}'
```

Show Deployment selector:

```bash
kubectl get deployment/<deployment> -n <namespace> \
  -o jsonpath='{.spec.selector.matchLabels}'; echo
```

### StatefulSets

```bash
kubectl get statefulset -n <namespace>
kubectl describe statefulset/<statefulset> -n <namespace>
kubectl get statefulset/<statefulset> -n <namespace> -o yaml
kubectl rollout status statefulset/<statefulset> -n <namespace>
```

### DaemonSets

```bash
kubectl get daemonset -A
kubectl describe daemonset/<daemonset> -n <namespace>
kubectl rollout status daemonset/<daemonset> -n <namespace>
```

### Jobs and CronJobs

```bash
kubectl get jobs,cronjobs -n <namespace>
kubectl describe job/<job> -n <namespace>
kubectl logs job/<job> -n <namespace>
kubectl get cronjob/<cronjob> -n <namespace> -o yaml
```

Create a one-time Job from a CronJob:

```bash
kubectl create job \
  --from=cronjob/<cronjob> \
  <cronjob>-manual-$(date +%Y%m%d%H%M%S) \
  -n <namespace>
```

---

## 7. Pod Troubleshooting

List Pods:

```bash
kubectl get pods -n <namespace>
kubectl get pods -n <namespace> -o wide
kubectl get pods -n <namespace> --show-labels
```

Describe a Pod:

```bash
kubectl describe pod/<pod> -n <namespace>
```

Show full manifest and status:

```bash
kubectl get pod/<pod> -n <namespace> -o yaml
```

Show Pod conditions:

```bash
kubectl get pod/<pod> -n <namespace> \
  -o jsonpath='{range .status.conditions[*]}{.type}{"="}{.status}{" reason="}{.reason}{" message="}{.message}{"\n"}{end}'
```

Show container restart counts:

```bash
kubectl get pod/<pod> -n <namespace> \
  -o jsonpath='{range .status.containerStatuses[*]}{.name}{" restarts="}{.restartCount}{" ready="}{.ready}{"\n"}{end}'
```

Show waiting and termination reasons:

```bash
kubectl get pod/<pod> -n <namespace> \
  -o jsonpath='{range .status.containerStatuses[*]}{.name}{" waiting="}{.state.waiting.reason}{" terminated="}{.state.terminated.reason}{" exitCode="}{.state.terminated.exitCode}{"\n"}{end}'
```

Show init container status:

```bash
kubectl get pod/<pod> -n <namespace> \
  -o jsonpath='{range .status.initContainerStatuses[*]}{.name}{" ready="}{.ready}{" state="}{.state}{"\n"}{end}'
```

Find Pods on a node:

```bash
kubectl get pods -A --field-selector=spec.nodeName=<node> -o wide
```

Find Pods by label:

```bash
kubectl get pods -n <namespace> -l app=<application>
kubectl get pods -n <namespace> -l '<key> in (<value1>,<value2>)'
```

Events for one Pod:

```bash
kubectl get events -n <namespace> \
  --field-selector=involvedObject.name=<pod> \
  --sort-by=.metadata.creationTimestamp
```

Wait for Pod readiness:

```bash
kubectl wait pod/<pod> -n <namespace> \
  --for=condition=Ready \
  --timeout=120s
```

---

## 8. Logs

Current logs:

```bash
kubectl logs pod/<pod> -n <namespace>
```

Follow logs:

```bash
kubectl logs -f pod/<pod> -n <namespace>
```

Specific container:

```bash
kubectl logs pod/<pod> -c <container> -n <namespace>
```

Previous crashed container:

```bash
kubectl logs pod/<pod> -c <container> -n <namespace> --previous
```

Recent lines:

```bash
kubectl logs pod/<pod> -n <namespace> --tail=200
```

Logs from the last 30 minutes:

```bash
kubectl logs pod/<pod> -n <namespace> --since=30m
```

Logs with timestamps:

```bash
kubectl logs pod/<pod> -n <namespace> --timestamps
```

Logs from all containers:

```bash
kubectl logs pod/<pod> -n <namespace> \
  --all-containers=true \
  --prefix \
  --tail=200
```

Logs from Pods matching a label:

```bash
kubectl logs -n <namespace> \
  -l app=<application> \
  --all-containers=true \
  --prefix \
  --tail=200
```

Deployment logs:

```bash
kubectl logs deployment/<deployment> -n <namespace> --tail=200
```

---

## 9. Execute, Debug, Copy, and Port Forward

Open a shell:

```bash
kubectl exec -it pod/<pod> -n <namespace> -- /bin/bash
kubectl exec -it pod/<pod> -n <namespace> -- /bin/sh
```

Specific container:

```bash
kubectl exec -it pod/<pod> -c <container> -n <namespace> -- /bin/sh
```

Execute one command:

```bash
kubectl exec pod/<pod> -n <namespace> -- env
kubectl exec pod/<pod> -n <namespace> -- cat /etc/resolv.conf
```

Copy a file from a Pod:

```bash
kubectl cp <namespace>/<pod>:/path/in/container ./local-file \
  -c <container>
```

Copy a file into a Pod:

```bash
kubectl cp ./local-file <namespace>/<pod>:/path/in/container \
  -c <container>
```

> `kubectl cp` normally requires `tar` to exist in the container.

Create an ephemeral debug container:

```bash
kubectl debug -it pod/<pod> -n <namespace> \
  --image=<approved-debug-image> \
  --target=<container>
```

Create a copied debug Pod:

```bash
kubectl debug pod/<pod> -n <namespace> \
  -it \
  --copy-to=<pod>-debug \
  --image=<approved-debug-image>
```

Debug a node, subject to elevated permissions:

```bash
kubectl debug node/<node> -it --image=<approved-debug-image>
```

Port-forward a Service:

```bash
kubectl port-forward service/<service> -n <namespace> \
  <local-port>:<service-port>
```

Port-forward a Deployment:

```bash
kubectl port-forward deployment/<deployment> -n <namespace> \
  <local-port>:<container-port>
```

---

## 10. Rollouts, Restarts, Scaling, and Images

Rollout status:

```bash
kubectl rollout status deployment/<deployment> -n <namespace>
kubectl rollout status statefulset/<statefulset> -n <namespace>
kubectl rollout status daemonset/<daemonset> -n <namespace>
```

Rollout history:

```bash
kubectl rollout history deployment/<deployment> -n <namespace>
kubectl rollout history deployment/<deployment> -n <namespace> --revision=<revision>
```

Restart a workload:

```bash
kubectl rollout restart deployment/<deployment> -n <namespace>
kubectl rollout restart statefulset/<statefulset> -n <namespace>
kubectl rollout restart daemonset/<daemonset> -n <namespace>
```

Pause and resume a Deployment rollout:

```bash
kubectl rollout pause deployment/<deployment> -n <namespace>
kubectl rollout resume deployment/<deployment> -n <namespace>
```

Undo to the previous revision:

```bash
kubectl rollout undo deployment/<deployment> -n <namespace>
```

Undo to a selected revision:

```bash
kubectl rollout undo deployment/<deployment> -n <namespace> \
  --to-revision=<revision>
```

Scale:

```bash
kubectl scale deployment/<deployment> -n <namespace> --replicas=<count>
kubectl scale statefulset/<statefulset> -n <namespace> --replicas=<count>
```

Set an image directly:

```bash
kubectl set image deployment/<deployment> -n <namespace> \
  <container>=<registry>/<image>:<tag>
```

> In a GitOps environment, commit the image or manifest change to Git instead of relying on a direct cluster update.

Wait for Deployment availability:

```bash
kubectl wait deployment/<deployment> -n <namespace> \
  --for=condition=Available \
  --timeout=180s
```

---

## 11. Services, Endpoints, and DNS

List Services:

```bash
kubectl get services -n <namespace>
kubectl get services -A -o wide
```

Describe a Service:

```bash
kubectl describe service/<service> -n <namespace>
kubectl get service/<service> -n <namespace> -o yaml
```

Show selector and ports:

```bash
kubectl get service/<service> -n <namespace> \
  -o jsonpath='selector={.spec.selector}{"\n"}ports={.spec.ports}{"\n"}'
```

Check Endpoints and EndpointSlices:

```bash
kubectl get endpoints/<service> -n <namespace> -o wide
kubectl get endpointslice -n <namespace> \
  -l kubernetes.io/service-name=<service>
```

Compare Service selector with Pod labels:

```bash
kubectl get service/<service> -n <namespace> \
  -o jsonpath='{.spec.selector}'; echo

kubectl get pods -n <namespace> --show-labels
```

Test DNS using an approved BusyBox-like image:

```bash
kubectl run dns-test \
  -n <namespace> \
  --rm -it \
  --restart=Never \
  --image=<approved-dns-test-image> \
  -- nslookup <service>.<namespace>.svc.cluster.local
```

Test an HTTP endpoint from inside the cluster:

```bash
kubectl run curl-test \
  -n <namespace> \
  --rm -it \
  --restart=Never \
  --image=<approved-curl-image> \
  -- curl -vk http://<service>:<port>/<path>
```

Review NetworkPolicies:

```bash
kubectl get networkpolicy -n <namespace>
kubectl describe networkpolicy/<policy> -n <namespace>
```

---

## 12. Ingress and Traefik

List standard Ingress resources:

```bash
kubectl get ingress -A
kubectl get ingress -n <namespace> -o wide
kubectl describe ingress/<ingress> -n <namespace>
kubectl get ingress/<ingress> -n <namespace> -o yaml
```

List IngressClasses:

```bash
kubectl get ingressclass
kubectl describe ingressclass/<class>
```

Discover Traefik CRDs:

```bash
kubectl api-resources | grep -Ei 'ingressroute|middleware|traefikservice|tlsoption|tlsstore'
kubectl get crd | grep -i traefik
```

List common Traefik custom resources:

```bash
kubectl get ingressroutes.traefik.io -A
kubectl get middlewares.traefik.io -A
kubectl get traefikservices.traefik.io -A
kubectl get tlsoptions.traefik.io -A
kubectl get tlsstores.traefik.io -A
```

Inspect an IngressRoute:

```bash
kubectl describe ingressroute/<route> -n <namespace>
kubectl get ingressroute/<route> -n <namespace> -o yaml
```

Find the Traefik workload:

```bash
kubectl get pods,deployments,daemonsets -A | grep -i traefik
```

Inspect Traefik logs after identifying namespace and workload type:

```bash
kubectl logs daemonset/<traefik-daemonset> \
  -n <traefik-namespace> \
  --all-containers=true \
  --tail=300

kubectl logs deployment/<traefik-deployment> \
  -n <traefik-namespace> \
  --all-containers=true \
  --tail=300
```

Check Traefik Service and ports:

```bash
kubectl get service -n <traefik-namespace>
kubectl describe service/<traefik-service> -n <traefik-namespace>
```

Trace an exposed route:

```text
Ingress / IngressRoute
        ↓
Middleware, if configured
        ↓
Service
        ↓
EndpointSlice / Endpoints
        ↓
Ready Pod
        ↓
Container listening on targetPort
```

Commands for the trace:

```bash
kubectl get ingress,service,pod -n <namespace> -o wide
kubectl get ingressroute,middleware,traefikservice -n <namespace>
kubectl get endpoints,endpointslice -n <namespace>
```

---

## 13. ConfigMaps and Secrets

List ConfigMaps:

```bash
kubectl get configmap -n <namespace>
kubectl describe configmap/<configmap> -n <namespace>
kubectl get configmap/<configmap> -n <namespace> -o yaml
```

List Secret metadata only:

```bash
kubectl get secret -n <namespace>
kubectl describe secret/<secret> -n <namespace>
```

Show Secret keys without exposing values:

```bash
kubectl get secret/<secret> -n <namespace> \
  -o jsonpath='{range $key,$value := .data}{$key}{"\n"}{end}'
```

Find Pods referencing a ConfigMap:

```bash
kubectl get pods -n <namespace> -o yaml | grep -n -B3 -A5 '<configmap>'
```

Find Pods referencing a Secret:

```bash
kubectl get pods -n <namespace> -o yaml | grep -n -B3 -A5 '<secret>'
```

> Decode Secret values only when explicitly authorized, and never paste them into shared output.

---

## 14. Storage: StorageClasses, PVCs, and PVs

List StorageClasses:

```bash
kubectl get storageclass
kubectl get sc -o wide
kubectl describe storageclass/<storageclass>
```

Inspect a selected StorageClass:

```bash
kubectl describe storageclass/<storageclass>
```

List PVCs:

```bash
kubectl get pvc -A
kubectl get pvc -n <namespace> -o wide
kubectl describe pvc/<pvc> -n <namespace>
```

List PVs:

```bash
kubectl get pv
kubectl get pv -o wide
kubectl describe pv/<pv>
```

Show PVC-to-PV mapping:

```bash
kubectl get pvc -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,PVC:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName,CLASS:.spec.storageClassName,REQUESTED:.spec.resources.requests.storage'
```

Show PV reclaim policies:

```bash
kubectl get pv \
  -o custom-columns='PV:.metadata.name,STATUS:.status.phase,CLAIM:.spec.claimRef.namespace/.spec.claimRef.name,CLASS:.spec.storageClassName,RECLAIM:.spec.persistentVolumeReclaimPolicy,CAPACITY:.spec.capacity.storage'
```

Find Pods using a PVC:

```bash
kubectl get pods -n <namespace> \
  -o jsonpath='{range .items[*]}{.metadata.name}{": "}{range .spec.volumes[*]}{.persistentVolumeClaim.claimName}{" "}{end}{"\n"}{end}' \
  | grep '<pvc>'
```

Inspect volume mounts for one Pod:

```bash
kubectl get pod/<pod> -n <namespace> \
  -o jsonpath='{range .spec.containers[*]}{"CONTAINER: "}{.name}{"\n"}{range .volumeMounts[*]}{"  "}{.name}{" -> "}{.mountPath}{"\n"}{end}{end}'
```

PVCs not in `Bound` state:

```bash
kubectl get pvc -A \
  --field-selector=status.phase!=Bound
```

Storage-related events:

```bash
kubectl get events -A \
  --sort-by=.metadata.creationTimestamp \
  | grep -Ei 'volume|pvc|mount|attach|provision'
```

Check CSI components:

```bash
kubectl get csidrivers
kubectl get csinodes
kubectl get volumeattachments
kubectl get pods -A | grep -Ei 'csi|storage|provisioner'
```

---

## 15. RBAC and Access Checks

Check whether the current identity can perform an action:

```bash
kubectl auth can-i get pods -n <namespace>
kubectl auth can-i create deployments -n <namespace>
kubectl auth can-i delete pods -n <namespace>
```

List all allowed actions in a namespace:

```bash
kubectl auth can-i --list -n <namespace>
```

Check cluster-scoped access:

```bash
kubectl auth can-i get nodes
kubectl auth can-i list namespaces
```

Check as another user, when impersonation is permitted:

```bash
kubectl auth can-i get pods \
  -n <namespace> \
  --as=<user>
```

Check as a ServiceAccount:

```bash
kubectl auth can-i get pods \
  -n <namespace> \
  --as=system:serviceaccount:<namespace>:<serviceaccount>
```

List RBAC objects:

```bash
kubectl get roles,rolebindings -A
kubectl get clusterroles,clusterrolebindings
kubectl get serviceaccounts -A
```

Inspect a RoleBinding:

```bash
kubectl describe rolebinding/<binding> -n <namespace>
kubectl get rolebinding/<binding> -n <namespace> -o yaml
```

Inspect a ClusterRoleBinding:

```bash
kubectl describe clusterrolebinding/<binding>
kubectl get clusterrolebinding/<binding> -o yaml
```

Find bindings referencing a user, group, or ServiceAccount:

```bash
kubectl get rolebindings -A -o yaml | grep -n -B5 -A8 '<subject>'
kubectl get clusterrolebindings -o yaml | grep -n -B5 -A8 '<subject>'
```

---

## 16. Nodes, Scheduling, and Maintenance

Show scheduling-relevant information:

```bash
kubectl get nodes -o wide
kubectl describe node/<node>
kubectl get node/<node> --show-labels
kubectl get node/<node> -o jsonpath='{.spec.taints}'; echo
```

List Pods scheduled on a node:

```bash
kubectl get pods -A \
  --field-selector=spec.nodeName=<node> \
  -o wide
```

Show allocatable resources:

```bash
kubectl get node/<node> \
  -o jsonpath='CPU={.status.allocatable.cpu} MEMORY={.status.allocatable.memory} PODS={.status.allocatable.pods}{"\n"}'
```

Show node conditions:

```bash
kubectl get node/<node> \
  -o jsonpath='{range .status.conditions[*]}{.type}{"="}{.status}{" reason="}{.reason}{" message="}{.message}{"\n"}{end}'
```

Cordon a node:

```bash
kubectl cordon <node>
```

Check PodDisruptionBudgets before draining:

```bash
kubectl get poddisruptionbudget -A
```

Drain a node:

```bash
kubectl drain <node> \
  --ignore-daemonsets \
  --delete-emptydir-data
```

> `--delete-emptydir-data` permanently removes data stored in `emptyDir` volumes on evicted Pods.

Return the node to service:

```bash
kubectl uncordon <node>
```

---

## 17. Resource Requests, Limits, and Quotas

Show container requests and limits:

```bash
kubectl get pods -n <namespace> \
  -o custom-columns='POD:.metadata.name,CONTAINER:.spec.containers[*].name,CPU_REQUEST:.spec.containers[*].resources.requests.cpu,MEM_REQUEST:.spec.containers[*].resources.requests.memory,CPU_LIMIT:.spec.containers[*].resources.limits.cpu,MEM_LIMIT:.spec.containers[*].resources.limits.memory'
```

Show namespace quotas:

```bash
kubectl get resourcequota -n <namespace>
kubectl describe resourcequota -n <namespace>
```

Show LimitRanges:

```bash
kubectl get limitrange -n <namespace>
kubectl describe limitrange -n <namespace>
```

Show HorizontalPodAutoscalers:

```bash
kubectl get hpa -A
kubectl describe hpa/<hpa> -n <namespace>
```

---

## 18. Labels, Annotations, Selectors, and JSONPath

Show labels:

```bash
kubectl get pods -n <namespace> --show-labels
kubectl get namespace/<namespace> --show-labels
```

Apply a label:

```bash
kubectl label <resource>/<name> \
  <key>=<value> \
  -n <namespace>
```

Remove a label:

```bash
kubectl label <resource>/<name> \
  <key>- \
  -n <namespace>
```

Apply an annotation:

```bash
kubectl annotate <resource>/<name> \
  <key>=<value> \
  -n <namespace>
```

Remove an annotation:

```bash
kubectl annotate <resource>/<name> \
  <key>- \
  -n <namespace>
```

Select by label:

```bash
kubectl get pods -n <namespace> -l <key>=<value>
kubectl get pods -n <namespace> -l '<key>!=<value>'
```

Common output formats:

```bash
kubectl get pod/<pod> -n <namespace> -o yaml
kubectl get pod/<pod> -n <namespace> -o json
kubectl get pods -n <namespace> -o wide
kubectl get pods -n <namespace> -o name
```

Custom columns:

```bash
kubectl get pods -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,POD:.metadata.name,NODE:.spec.nodeName,PHASE:.status.phase'
```

JSONPath example:

```bash
kubectl get pods -n <namespace> \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'
```

---

## 19. Helm Operational Commands

Show client version:

```bash
helm version
```

List releases:

```bash
helm list -A
helm list -n <namespace>
helm list -n <namespace> --all
helm list -n <namespace> --failed
```

Release status:

```bash
helm status <release> -n <namespace>
```

Show release values:

```bash
helm get values <release> -n <namespace>
helm get values <release> -n <namespace> --all
```

Show rendered release manifest:

```bash
helm get manifest <release> -n <namespace>
```

Show all stored release information:

```bash
helm get all <release> -n <namespace>
```

Release history:

```bash
helm history <release> -n <namespace>
```

Render locally:

```bash
helm template <release> <chart> \
  -n <namespace> \
  -f <values.yaml>
```

Lint a chart:

```bash
helm lint <chart-directory>
```

Upgrade simulation:

```bash
helm upgrade <release> <chart> \
  -n <namespace> \
  -f <values.yaml> \
  --dry-run
```

Rollback:

```bash
helm rollback <release> <revision> \
  -n <namespace> \
  --wait
```

> Confirm whether the release is managed by Argo CD before executing Helm changes directly.

---

## 20. Argo CD Operational Commands

Find Argo CD components:

```bash
kubectl get pods,deployments,statefulsets,services -A | grep -i argocd
```

List Application resources:

```bash
kubectl get applications.argoproj.io -A
kubectl get applicationsets.argoproj.io -A
kubectl get appprojects.argoproj.io -A
```

Inspect an Application:

```bash
kubectl describe application/<application> -n <argocd-namespace>
kubectl get application/<application> -n <argocd-namespace> -o yaml
```

Show application sync and health status:

```bash
kubectl get application/<application> -n <argocd-namespace> \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status} revision={.status.sync.revision}{"\n"}'
```

Show Application conditions:

```bash
kubectl get application/<application> -n <argocd-namespace> \
  -o jsonpath='{range .status.conditions[*]}{.type}{": "}{.message}{"\n"}{end}'
```

Argo CD CLI login:

```bash
argocd login <argocd-server>
```

List applications:

```bash
argocd app list
```

Inspect an application:

```bash
argocd app get <application>
argocd app get <application> --show-operation
```

Show differences:

```bash
argocd app diff <application>
```

Refresh application state:

```bash
argocd app get <application> --refresh
argocd app get <application> --hard-refresh
```

Sync an application:

```bash
argocd app sync <application>
argocd app wait <application> --health --sync --timeout 300
```

Show history:

```bash
argocd app history <application>
```

Rollback through Argo CD:

```bash
argocd app rollback <application> <history-id>
```

> Before a manual sync, verify the Git revision, target cluster, namespace, sync window, and required approval.

---

## 21. Manifest Operations

Create or update resources:

```bash
kubectl apply -f <manifest.yaml>
kubectl apply -f <directory>
kubectl apply -k <kustomize-directory>
```

Validate on the API server without persisting:

```bash
kubectl apply --dry-run=server -f <manifest.yaml>
```

Show differences:

```bash
kubectl diff -f <manifest.yaml>
kubectl diff -k <kustomize-directory>
```

Generate YAML without creating a resource:

```bash
kubectl create namespace <namespace> \
  --dry-run=client \
  -o yaml

kubectl create configmap <configmap> \
  -n <namespace> \
  --from-file=<file> \
  --dry-run=client \
  -o yaml
```

Export a live resource:

```bash
kubectl get <resource>/<name> -n <namespace> -o yaml \
  > <name>.yaml
```

---

## 22. Destructive Operations — High Risk

Delete one Pod and allow its controller to recreate it:

```bash
kubectl delete pod/<pod> -n <namespace>
```

Delete a resource:

```bash
kubectl delete <resource>/<name> -n <namespace>
```

Delete from a manifest:

```bash
kubectl delete -f <manifest.yaml>
```

Force-delete a stuck Pod:

```bash
kubectl delete pod/<pod> -n <namespace> \
  --grace-period=0 \
  --force
```

Delete all Pods matching a label:

```bash
kubectl delete pods -n <namespace> -l <key>=<value>
```

Delete a namespace:

```bash
kubectl delete namespace/<namespace>
```

### Do not run casually

```bash
kubectl delete pvc/<pvc> -n <namespace>
kubectl delete pv/<pv>
kubectl delete crd/<crd>
kubectl delete namespace/<namespace>
helm uninstall <release> -n <namespace>
```

Before deleting anything:

```bash
kubectl get <resource>/<name> -n <namespace> -o yaml \
  > backup-<resource>-<name>.yaml

kubectl auth can-i delete <resource> -n <namespace>
```

Also confirm:

- Ownership and controller relationship
- Argo CD or Helm management
- Storage reclaim policy
- Backup and restore availability
- Dependent workloads and services
- Approval and maintenance window

---

## 23. Common Operational One-Liners

Pods using a specific image:

```bash
kubectl get pods -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{" "}{end}{"\n"}{end}' \
  | grep '<image>'
```

All container images in the cluster:

```bash
kubectl get pods -A \
  -o jsonpath='{range .items[*].spec.containers[*]}{.image}{"\n"}{end}' \
  | sort -u
```

Pods with restart counts:

```bash
kubectl get pods -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,POD:.metadata.name,RESTARTS:.status.containerStatuses[*].restartCount'
```

Pods on each node:

```bash
kubectl get pods -A \
  -o custom-columns='NODE:.spec.nodeName,NAMESPACE:.metadata.namespace,POD:.metadata.name,PHASE:.status.phase' \
  --sort-by=.spec.nodeName
```

Workloads with replica mismatch:

```bash
kubectl get deployment -A \
  -o custom-columns='NAMESPACE:.metadata.namespace,DEPLOYMENT:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas'
```

Services without Endpoints:

```bash
for item in $(kubectl get svc -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'); do
  ns="${item%/*}"
  svc="${item#*/}"
  addresses="$(kubectl get endpoints "$svc" -n "$ns" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)"
  if [ -z "$addresses" ]; then
    echo "$ns/$svc"
  fi
done
```

Recent warning events:

```bash
kubectl get events -A \
  --field-selector=type=Warning \
  --sort-by=.lastTimestamp \
  | tail -50
```

Resources marked for deletion:

```bash
kubectl get pods -A \
  -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.namespace}{"/"}{.metadata.name}{"\t"}{.metadata.deletionTimestamp}{"\n"}{end}'
```

---

## 24. Quick Incident Investigation Flow

### Step 1 — Confirm scope

```bash
kubectl config current-context
kubectl get namespace/<namespace>
kubectl get pods -n <namespace> -o wide
```

### Step 2 — Check workload state

```bash
kubectl get deployment,statefulset,daemonset,job -n <namespace>
kubectl describe <workload-type>/<workload> -n <namespace>
```

### Step 3 — Inspect the affected Pod

```bash
kubectl describe pod/<pod> -n <namespace>
kubectl logs pod/<pod> -n <namespace> --all-containers=true --tail=200
kubectl logs pod/<pod> -n <namespace> --all-containers=true --previous
```

### Step 4 — Check events

```bash
kubectl get events -n <namespace> \
  --sort-by=.metadata.creationTimestamp
```

### Step 5 — Validate networking

```bash
kubectl get service,endpoints,endpointslice,ingress -n <namespace>
kubectl get ingressroute,middleware,traefikservice -n <namespace>
```

### Step 6 — Validate storage

```bash
kubectl get pvc -n <namespace>
kubectl describe pvc/<pvc> -n <namespace>
kubectl get pv
```

### Step 7 — Validate access and configuration

```bash
kubectl auth can-i --list -n <namespace>
kubectl get configmap,secret -n <namespace>
```

### Step 8 — Check GitOps ownership

```bash
kubectl get applications.argoproj.io -A
argocd app get <application>
argocd app diff <application>
```

### Step 9 — Capture evidence before remediation

```bash
kubectl get <resource>/<name> -n <namespace> -o yaml \
  > <resource>-<name>-incident.yaml

kubectl get events -n <namespace> \
  --sort-by=.metadata.creationTimestamp \
  > <namespace>-events.txt

kubectl logs pod/<pod> -n <namespace> \
  --all-containers=true \
  --timestamps \
  > <pod>-logs.txt
```

### Step 10 — Apply the least disruptive approved action

Typical progression:

1. Refresh or resync through Argo CD.
2. Restart only the affected workload.
3. Recreate only the affected Pod.
4. Roll back to a known good Git or Helm revision.
5. Escalate node, storage, networking, or control-plane issues.

---

## 25. Useful Shell Setup

Configure the short alias:

```bash
echo "alias k=kubectl" >> ~/.bashrc
source ~/.bashrc
```

Enable Bash completion:

```bash
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
```

Persist completion:

```bash
cat <<'EOF' >> ~/.bashrc

alias k=kubectl
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
EOF
```

Useful namespace helper:

```bash
kns() {
  kubectl config set-context --current --namespace="$1"
}
```

Usage:

```bash
kns <namespace>
```

---

## 26. Official References

- Kubernetes kubectl Quick Reference: https://kubernetes.io/docs/reference/kubectl/quick-reference/
- Kubernetes Debugging: https://kubernetes.io/docs/tasks/debug/
- Kubernetes `kubectl auth can-i`: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_can-i/
- Kubernetes StorageClasses: https://kubernetes.io/docs/concepts/storage/storage-classes/
- Kubernetes Safe Node Drain: https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/
- Argo CD command reference: https://argo-cd.readthedocs.io/en/latest/user-guide/commands/argocd/
- Traefik Kubernetes CRD provider: https://doc.traefik.io/traefik/providers/kubernetes-crd/
- Helm commands: https://helm.sh/docs/helm/

---

## 27. Recommended Repository Location

Suggested filename:

```text
k8s-operational-command-cheat-sheet.md
```

Possible repository structure:

```text
k8s-support-toolkit/
└── k8s-operational-command-cheat-sheet/
    └── k8s-operational-command-cheat-sheet.md
```