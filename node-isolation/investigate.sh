#!/bin/bash
# Collect forensic information from a node under investigation
# Run on the control plane node. Uses kubectl for API data,
# then guides through direct node access for runtime forensics.
#
# Usage: ./investigate.sh <node-name>

set -euo pipefail

NODE="${1:-}"
REPORT_DIR="/tmp/incident-$(date +%Y%m%d-%H%M%S)-${NODE}"

if [[ -z "$NODE" ]]; then
  echo "Usage: $0 <node-name>"
  exit 1
fi

mkdir -p "$REPORT_DIR"
echo "Collecting forensics for node: $NODE"
echo "Report directory: $REPORT_DIR"

# 1. Collect pod information from the node
echo "[1/7] Collecting pod list..."
kubectl get pods --all-namespaces \
  --field-selector "spec.nodeName=${NODE}" \
  -o wide > "${REPORT_DIR}/pods-on-node.txt" 2>&1

# 2. Collect pod details (including security contexts)
echo "[2/7] Collecting pod security contexts..."
kubectl get pods --all-namespaces \
  --field-selector "spec.nodeName=${NODE}" \
  -o json > "${REPORT_DIR}/pods-full.json" 2>&1

# 3. Extract containers with privileged flag
echo "[3/7] Checking for privileged containers..."
jq '.items[] | select(.spec.containers[].securityContext.privileged==true) |
  {name: .metadata.name, namespace: .metadata.namespace}' \
  "${REPORT_DIR}/pods-full.json" > "${REPORT_DIR}/privileged-containers.json" 2>/dev/null || echo "none"

# 4. Check for hostPath mounts
echo "[4/7] Checking for hostPath volume mounts..."
jq '.items[] | select(.spec.volumes[]?.hostPath != null) |
  {name: .metadata.name, namespace: .metadata.namespace, volumes: [.spec.volumes[].hostPath.path]}' \
  "${REPORT_DIR}/pods-full.json" > "${REPORT_DIR}/hostpath-mounts.json" 2>/dev/null || echo "none"

# 5. Collect recent events for the node
echo "[5/7] Collecting events..."
kubectl get events --all-namespaces \
  --field-selector "involvedObject.name=${NODE}" \
  --sort-by='.lastTimestamp' > "${REPORT_DIR}/node-events.txt" 2>&1

# 6. Collect RBAC bindings
echo "[6/7] Collecting RBAC bindings..."
kubectl get rolebindings,clusterrolebindings --all-namespaces -o wide \
  > "${REPORT_DIR}/rbac-bindings.txt" 2>&1

# 7. Recent audit log entries for this node's pods
echo "[7/7] Checking audit log for suspicious exec/attach events..."
if [[ -f "/var/log/kubernetes/audit.log" ]]; then
  grep -E '"verb":"(exec|attach|create).*pods' /var/log/kubernetes/audit.log | \
    tail -100 > "${REPORT_DIR}/audit-exec-events.txt" 2>&1
  echo "Audit log parsed."
else
  echo "Audit log not accessible from this host. Access directly on control plane." \
    > "${REPORT_DIR}/audit-exec-events.txt"
fi

echo ""
echo "=== Collection complete. Report: $REPORT_DIR ==="
echo ""
echo "=== Runtime forensics (requires direct node access) ==="
echo "SSH to the node and run the following:"
echo ""
echo "  # Check running processes"
echo "  ps auxf | grep -v '\\['"
echo ""
echo "  # Check open network connections"
echo "  ss -tulpn"
echo ""
echo "  # Check for suspicious cron entries"
echo "  crontab -l; ls -la /etc/cron*"
echo ""
echo "  # Check recently modified files"
echo "  find / -mmin -60 -not -path '/proc/*' -not -path '/sys/*' 2>/dev/null | head -50"
echo ""
echo "  # Check container runtime for suspicious layers"
echo "  crictl ps -a"
echo "  crictl images | sort -k4 -rh | head -20"
echo ""
echo "  # Check for suspicious capabilities"
echo "  capsh --print"
