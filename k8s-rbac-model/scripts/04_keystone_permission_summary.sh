#!/usr/bin/env bash

set -euo pipefail

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="$(dirname "${SCRIPT_DIR}")"
OUTPUT_DIR="${MODULE_DIR}/outputs/keystone_permission_summary_${TIMESTAMP}"
OUTPUT_FILE="${OUTPUT_DIR}/keystone_permission_summary.txt"

mkdir -p "${OUTPUT_DIR}"

python3 >"${OUTPUT_FILE}" <<'PY'
import hashlib
import json
import subprocess


def mask_identifier(value):
    digest = hashlib.sha256(value.encode()).hexdigest()[:12]
    return f"<masked:{digest}>"


configmap = json.loads(
    subprocess.check_output(
        [
            "kubectl",
            "get",
            "configmap",
            "k8s-keystone-auth-policy",
            "--namespace",
            "kube-system",
            "-o",
            "json",
        ],
        text=True,
    )
)

raw_policies = (
    configmap.get("data", {}).get("policies")
)

if not raw_policies:
    raise SystemExit(
        "The ConfigMap does not contain a policies key."
    )

policies = json.loads(raw_policies)

print("# Keystone Permission Summary")
print()
print(f"Policy count: {len(policies)}")
print()

for index, policy in enumerate(policies, start=1):
    print(f"## Policy {index}")
    print()

    users = policy.get("users") or {}

    roles = users.get("roles") or []
    projects = users.get("projects") or []
    domains = users.get("domains") or []
    usernames = users.get("names") or users.get("usernames") or []

    print(
        "Roles: "
        + (", ".join(roles) if roles else "<not restricted>")
    )

    print(
        "Projects: "
        + (
            ", ".join(mask_identifier(value) for value in projects)
            if projects
            else "<not restricted>"
        )
    )

    print(
        "Domains: "
        + (
            ", ".join(mask_identifier(value) for value in domains)
            if domains
            else "<not restricted>"
        )
    )

    print(
        "Usernames: "
        + (
            ", ".join(mask_identifier(value) for value in usernames)
            if usernames
            else "<not restricted>"
        )
    )

    print()
    print("Resource permissions:")

    resource_permissions = (
        policy.get("resource_permissions") or {}
    )

    if isinstance(resource_permissions, dict):
        permission_maps = [resource_permissions]
    elif isinstance(resource_permissions, list):
        permission_maps = resource_permissions
    else:
        permission_maps = []

    if not permission_maps:
        print("  <none>")

    for permission_map in permission_maps:
        for resource_expression, verbs in permission_map.items():
            verb_text = ", ".join(verbs)
            print(
                f"  - {resource_expression}: {verb_text}"
            )

    print()
    print("Non-resource permissions:")

    nonresource_permissions = (
        policy.get("nonresource_permissions") or {}
    )

    if isinstance(nonresource_permissions, dict):
        nonresource_maps = [nonresource_permissions]
    elif isinstance(nonresource_permissions, list):
        nonresource_maps = nonresource_permissions
    else:
        nonresource_maps = []

    if not nonresource_maps:
        print("  <none>")

    for permission_map in nonresource_maps:
        for path, verbs in permission_map.items():
            verb_text = ", ".join(verbs)
            print(f"  - {path}: {verb_text}")

    print()

    unrestricted = any(
        permission_map.get("*/*") == ["*"]
        for permission_map in permission_maps
    )

    if unrestricted:
        print(
            "Risk classification: unrestricted cluster access"
        )
    else:
        print(
            "Risk classification: restricted policy; review expressions"
        )

    print()
PY

echo "Keystone permission summary completed."
echo "Result: ${OUTPUT_FILE}"
