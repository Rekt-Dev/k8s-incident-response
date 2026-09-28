#!/bin/bash
# Audit RBAC bindings for overprivileged subjects
# Outputs a summary of bindings worth reviewing.

set -euo pipefail

echo "=== RBAC Audit Report ==="
echo "Generated: $(date)"
echo ""

echo "--- ClusterRoleBindings to cluster-admin ---"
kubectl get clusterrolebindings -o json | \
  jq -r '.items[] | select(.roleRef.name=="cluster-admin") |
    "Binding: \(.metadata.name)\n  Subjects: \([.subjects[]? | "\(.kind)/\(.name)"] | join(", "))\n"'

echo ""
echo "--- ClusterRoleBindings with wildcard resource access ---"
kubectl get clusterroles -o json | \
  jq -r '.items[] | . as $role | .rules[]? |
    select(.resources[]? == "*" and .verbs[]? == "*") |
    "ClusterRole: \($role.metadata.name)"' | sort -u

echo ""
echo "--- ServiceAccounts with ClusterRoleBindings ---"
kubectl get clusterrolebindings -o json | \
  jq -r '.items[] |
    . as $b | .subjects[]? |
    select(.kind == "ServiceAccount") |
    "ClusterRoleBinding: \($b.metadata.name)\n  SA: \(.namespace)/\(.name) -> \($b.roleRef.name)\n"'

echo ""
echo "--- RoleBindings granting cluster-admin or admin ---"
kubectl get rolebindings --all-namespaces -o json | \
  jq -r '.items[] | select(.roleRef.name == "cluster-admin" or .roleRef.name == "admin") |
    "[\(.metadata.namespace)] \(.metadata.name): \([.subjects[]? | "\(.kind)/\(.name)"] | join(", ")) -> \(.roleRef.name)"'

echo ""
echo "--- Pods with automountServiceAccountToken not disabled ---"
echo "(Pods where the SA token is mounted but the pod may not need it)"
kubectl get pods --all-namespaces -o json | \
  jq -r '.items[] |
    select(.spec.automountServiceAccountToken != false) |
    select(.spec.serviceAccountName != "default" or .spec.serviceAccountName == null) |
    "[\(.metadata.namespace)] \(.metadata.name) (SA: \(.spec.serviceAccountName // "default"))"' | \
  head -20

echo ""
echo "=== Audit complete ==="
