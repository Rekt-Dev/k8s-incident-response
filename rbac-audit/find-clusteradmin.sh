#!/bin/bash
# Find all principals with cluster-admin access
# cluster-admin is the most powerful role — binding anything to it
# grants unrestricted access to the entire cluster.

set -euo pipefail

echo "=== cluster-admin Access Audit ==="
echo ""

echo "Direct ClusterRoleBindings to cluster-admin:"
echo "--------------------------------------------"
kubectl get clusterrolebindings -o json | jq -r '
  .items[] |
  select(.roleRef.name == "cluster-admin") |
  "Binding: \(.metadata.name)",
  (.subjects[]? | "  \(.kind): \(if .namespace then .namespace + "/" else "" end)\(.name)"),
  ""
'

echo ""
echo "Default kubeadm cluster-admin bindings (expected):"
echo "  - system:masters group -> cluster-admin"
echo "  - kubeadm:cluster-admins group -> cluster-admin"
echo ""
echo "Any bindings above NOT in that list are worth reviewing."
echo ""

echo "Effective cluster-admin access via group membership:"
echo "(Groups that are bound to cluster-admin ClusterRoleBindings)"
kubectl get clusterrolebindings -o json | jq -r '
  .items[] |
  select(.roleRef.name == "cluster-admin") |
  .subjects[]? |
  select(.kind == "Group") |
  .name
' | sort -u
