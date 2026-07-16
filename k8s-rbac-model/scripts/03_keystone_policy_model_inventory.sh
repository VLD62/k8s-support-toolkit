#!/usr/bin/env bash

set -uo pipefail

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "${SCRIPT_DIR}")"
OUTPUT_DIR="${1:-${MODULE_DIR}/outputs/keystone_policy_model_${TIMESTAMP}}"

mkdir -p "${OUTPUT_DIR}"

LOG_FILE="${OUTPUT_DIR}/00_keystone_policy_model_execution.log"
STATUS_FILE="${OUTPUT_DIR}/00_keystone_policy_model_status.md"

SUCCESSFUL_CHECKS=0
FAILED_CHECKS=0

log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${message}" |
        tee -a "${LOG_FILE}"
}

run_check() {
    local description="$1"
    local output_file="$2"
    shift 2

    log "Collecting: ${description}"

    {
        echo "# ${description}"
        echo
        echo "Generated: $(date --iso-8601=seconds)"
        echo
        "$@"
    } >"${OUTPUT_DIR}/${output_file}" 2>&1

    local result=$?

    if [[ ${result} -eq 0 ]]; then
        log "SUCCESS: ${description}"
        SUCCESSFUL_CHECKS=$((SUCCESSFUL_CHECKS + 1))
    else
        log "FAILED OR ACCESS DENIED: ${description}"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi

    return 0
}

collect_apiserver_container_spec() {
    python3 <<'PY'
import json
import subprocess


def kubectl_json(arguments):
    return json.loads(
        subprocess.check_output(
            ["kubectl", *arguments, "-o", "json"],
            text=True,
        )
    )


pods = kubectl_json(
    ["get", "pods", "--namespace", "kube-system"]
)

matched = False

for pod in pods.get("items", []):
    metadata = pod.get("metadata", {})
    name = metadata.get("name", "")

    if not name.startswith("kube-apiserver-"):
        continue

    matched = True

    print(f"Pod: {name}")
    print(f"Node: {pod.get('spec', {}).get('nodeName', '')}")
    print()

    for container in pod.get("spec", {}).get("containers", []):
        print(f"Container: {container.get('name', '')}")
        print(f"Image: {container.get('image', '')}")
        print()

        print("Command:")

        command = container.get("command") or []

        if command:
            for value in command:
                print(f"  {value}")
        else:
            print("  <not present in Pod specification>")

        print()
        print("Arguments:")

        arguments = container.get("args") or []

        if arguments:
            for value in arguments:
                print(f"  {value}")
        else:
            print("  <not present in Pod specification>")

        print()
        print("Volume mounts:")

        for mount in container.get("volumeMounts", []) or []:
            print(
                f"  - {mount.get('name', '')}: "
                f"{mount.get('mountPath', '')} "
                f"(readOnly={mount.get('readOnly', False)})"
            )

        print()

    print("Volumes:")

    for volume in pod.get("spec", {}).get("volumes", []) or []:
        name = volume.get("name", "")
        source = "other"

        if "hostPath" in volume:
            source = (
                "hostPath:"
                + volume["hostPath"].get("path", "")
            )
        elif "configMap" in volume:
            source = (
                "configMap:"
                + volume["configMap"].get("name", "")
            )
        elif "secret" in volume:
            source = (
                "secret:"
                + volume["secret"].get("secretName", "")
            )

        print(f"  - {name}: {source}")

    print()

if not matched:
    print("No kube-apiserver Pod was visible.")
PY
}

collect_keystone_daemonset_spec() {
    python3 <<'PY'
import json
import re
import subprocess


SENSITIVE_NAME = re.compile(
    r"(password|passwd|token|secret|credential|"
    r"private.?key|client.?secret)",
    re.IGNORECASE,
)


data = json.loads(
    subprocess.check_output(
        [
            "kubectl",
            "get",
            "daemonset",
            "k8s-keystone-auth",
            "--namespace",
            "kube-system",
            "-o",
            "json",
        ],
        text=True,
    )
)

pod_spec = (
    data.get("spec", {})
    .get("template", {})
    .get("spec", {})
)

print(
    "ServiceAccount: "
    + str(pod_spec.get("serviceAccountName") or "default")
)
print(f"Host network: {pod_spec.get('hostNetwork', False)}")
print(f"Node selector: {pod_spec.get('nodeSelector', {})}")
print()

for container in pod_spec.get("containers", []):
    print(f"Container: {container.get('name', '')}")
    print(f"Image: {container.get('image', '')}")
    print()

    print("Command:")

    command = container.get("command") or []

    if command:
        for value in command:
            print(f"  {value}")
    else:
        print("  <image entrypoint>")

    print()
    print("Arguments:")

    arguments = container.get("args") or []

    if arguments:
        for value in arguments:
            print(f"  {value}")
    else:
        print("  <none>")

    print()
    print("Environment:")

    environment = container.get("env") or []

    if not environment:
        print("  <none>")

    for item in environment:
        name = item.get("name", "")

        if "valueFrom" in item:
            value_from = item["valueFrom"]

            if "secretKeyRef" in value_from:
                ref = value_from["secretKeyRef"]
                print(
                    f"  {name}=<Secret "
                    f"{ref.get('name', '')}/"
                    f"{ref.get('key', '')}>"
                )
            elif "configMapKeyRef" in value_from:
                ref = value_from["configMapKeyRef"]
                print(
                    f"  {name}=<ConfigMap "
                    f"{ref.get('name', '')}/"
                    f"{ref.get('key', '')}>"
                )
            elif "fieldRef" in value_from:
                print(
                    f"  {name}=<Field "
                    f"{value_from['fieldRef'].get('fieldPath', '')}>"
                )
            else:
                print(f"  {name}=<valueFrom>")
        else:
            value = str(item.get("value", ""))

            if SENSITIVE_NAME.search(name):
                value = "<REDACTED>"

            print(f"  {name}={value}")

    print()
    print("Volume mounts:")

    for mount in container.get("volumeMounts", []) or []:
        print(
            f"  - {mount.get('name', '')}: "
            f"{mount.get('mountPath', '')} "
            f"(readOnly={mount.get('readOnly', False)})"
        )

    print()

print("Volumes:")

for volume in pod_spec.get("volumes", []) or []:
    name = volume.get("name", "")
    source = "other"

    if "hostPath" in volume:
        source = (
            "hostPath:"
            + volume["hostPath"].get("path", "")
        )
    elif "configMap" in volume:
        source = (
            "configMap:"
            + volume["configMap"].get("name", "")
        )
    elif "secret" in volume:
        source = (
            "secret:"
            + volume["secret"].get("secretName", "")
        )

    print(f"  - {name}: {source}")
PY
}

collect_configmap_key_redacted() {
    local configmap_name="$1"
    local data_key="$2"

    python3 - "${configmap_name}" "${data_key}" <<'PY'
import hashlib
import json
import re
import subprocess
import sys


configmap_name = sys.argv[1]
data_key = sys.argv[2]

configmap = json.loads(
    subprocess.check_output(
        [
            "kubectl",
            "get",
            "configmap",
            configmap_name,
            "--namespace",
            "kube-system",
            "-o",
            "json",
        ],
        text=True,
    )
)

value = (configmap.get("data") or {}).get(data_key)

if value is None:
    print(
        f"ConfigMap {configmap_name} does not contain "
        f"the key {data_key}."
    )
    sys.exit(1)


sensitive_key = re.compile(
    r"^(.*?)(password|passwd|token|secret|credential|"
    r"private[_ -]?key|client[_ -]?secret|"
    r"application[_ -]?credential[_ -]?secret)"
    r"([^:=]*)(\s*[:=]\s*)(.*)$",
    re.IGNORECASE,
)

url_credentials = re.compile(
    r"(https?://[^:/@\s]+:)[^@\s]+@",
    re.IGNORECASE,
)


def redact(text):
    lines = []
    inside_private_key = False

    for line in text.splitlines():
        if "BEGIN PRIVATE KEY" in line:
            inside_private_key = True
            lines.append("<PRIVATE KEY REDACTED>")
            continue

        if inside_private_key:
            if "END PRIVATE KEY" in line:
                inside_private_key = False
            continue

        match = sensitive_key.match(line)

        if match:
            prefix = (
                match.group(1)
                + match.group(2)
                + match.group(3)
                + match.group(4)
            )
            lines.append(prefix + "<REDACTED>")
            continue

        line = url_credentials.sub(
            r"\1<REDACTED>@",
            line,
        )

        lines.append(line)

    return "\n".join(lines)


print(f"ConfigMap: kube-system/{configmap_name}")
print(f"Data key: {data_key}")
print(
    "Original SHA256: "
    + hashlib.sha256(value.encode()).hexdigest()
)
print()
print(redact(value))
PY
}

collect_keystone_serviceaccount_summary() {
    python3 <<'PY'
import json
import subprocess


data = json.loads(
    subprocess.check_output(
        [
            "kubectl",
            "get",
            "serviceaccount",
            "default",
            "--namespace",
            "kube-system",
            "-o",
            "json",
        ],
        text=True,
    )
)

metadata = data.get("metadata", {})

print(
    "ServiceAccount: "
    f"{metadata.get('namespace', '')}/"
    f"{metadata.get('name', '')}"
)
print(
    "Automount service account token: "
    f"{data.get('automountServiceAccountToken', '<default>')}"
)

print("Referenced Secrets:")

for item in data.get("secrets", []) or []:
    print(f"  - {item.get('name', '')}")

if not data.get("secrets"):
    print("  <none listed>")

print("Image pull Secrets:")

for item in data.get("imagePullSecrets", []) or []:
    print(f"  - {item.get('name', '')}")

if not data.get("imagePullSecrets"):
    print("  <none listed>")
PY
}

collect_webhook_related_flags() {
    python3 <<'PY'
import json
import subprocess


pods = json.loads(
    subprocess.check_output(
        [
            "kubectl",
            "get",
            "pods",
            "--namespace",
            "kube-system",
            "-o",
            "json",
        ],
        text=True,
    )
)

keywords = (
    "authorization",
    "authentication",
    "webhook",
    "anonymous-auth",
    "client-ca",
    "oidc",
    "requestheader",
    "service-account",
)

found = False

for pod in pods.get("items", []):
    name = pod.get("metadata", {}).get("name", "")

    if not name.startswith("kube-apiserver-"):
        continue

    for container in pod.get("spec", {}).get("containers", []):
        values = (
            (container.get("command") or [])
            + (container.get("args") or [])
        )

        for value in values:
            if any(keyword in value for keyword in keywords):
                found = True
                print(value)

if not found:
    print(
        "No authentication or authorization flags were "
        "visible in the kube-apiserver Pod specification."
    )
PY
}

if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERROR: kubectl is not available in PATH."
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required."
    exit 1
fi

log "Starting Keystone policy model inventory"
log "Output directory: ${OUTPUT_DIR}"

run_check \
    "Kubernetes API server complete container specification" \
    "01_apiserver_container_spec.txt" \
    collect_apiserver_container_spec

run_check \
    "Kubernetes API server webhook-related flags" \
    "02_apiserver_webhook_flags.txt" \
    collect_webhook_related_flags

run_check \
    "k8s-keystone-auth DaemonSet container specification" \
    "03_keystone_daemonset_spec.txt" \
    collect_keystone_daemonset_spec

run_check \
    "Redacted Keystone authorization policy" \
    "04_keystone_authorization_policy_redacted.txt" \
    collect_configmap_key_redacted \
    "k8s-keystone-auth-policy" \
    "policies"

run_check \
    "Redacted Keystone synchronization configuration" \
    "05_keystone_sync_config_redacted.txt" \
    collect_configmap_key_redacted \
    "k8s-keystone-auth-sync" \
    "syncConfig"

run_check \
    "Keystone default ServiceAccount summary" \
    "06_keystone_serviceaccount_summary.txt" \
    collect_keystone_serviceaccount_summary

run_check \
    "Keystone ClusterRole" \
    "07_keystone_clusterrole.yaml" \
    kubectl get clusterrole \
        system:k8s-keystone-auth \
        -o yaml

run_check \
    "Keystone ClusterRoleBinding" \
    "08_keystone_clusterrolebinding.yaml" \
    kubectl get clusterrolebinding \
        system:k8s-keystone-auth \
        -o yaml

{
    echo "# Keystone Policy Model Inventory Status"
    echo
    echo "- Generated: $(date --iso-8601=seconds)"
    echo "- Context: $(kubectl config current-context 2>/dev/null || echo unavailable)"
    echo "- Successful checks: ${SUCCESSFUL_CHECKS}"
    echo "- Failed or incomplete checks: ${FAILED_CHECKS}"
    echo "- Output directory: \`${OUTPUT_DIR}\`"
    echo
    echo "## Security"
    echo
    echo "Potential password, token, credential and private-key values are redacted."
    echo
    echo "Authorization policies, project names, role names and internal endpoints may still be operationally sensitive."
} >"${STATUS_FILE}"

log "Keystone policy model inventory completed"
log "Successful checks: ${SUCCESSFUL_CHECKS}"
log "Failed or incomplete checks: ${FAILED_CHECKS}"

echo
echo "Keystone policy model inventory completed."
echo "Results: ${OUTPUT_DIR}"
