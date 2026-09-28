#!/bin/bash
# Isolate a suspected compromised node
# This script cordons and drains the node, then applies a network policy
# to block all traffic to/from pods still on it.
#
# Usage: ./isolate-node.sh <node-name>
# Example: ./isolate-node.sh k8s1

set -euo pipefail

NODE="${1:-}"

if [[ -z "$NODE" ]]; then
  echo "Usage: $0 <node-name>"
  echo "Available nodes:"
  kubectl get nodes --no-headers -o custom-columns=":metadata.name"
  exit 1
fi

# Verify node exists
if ! kubectl get node "$NODE" &>/dev/null; then
  echo "ERROR: Node '$NODE' not found" >&2
  exit 1
fi

echo "=== Isolating node: $NODE ==="
echo "This will cordon, drain, and network-isolate the node."
echo "You have 10 seconds to abort (Ctrl+C)..."
sleep 10

# Step 1: Cordon — prevent new pods from being scheduled on this node
echo "[Step 1] Cordoning node..."
kubectl cordon "$NODE"
echo "Node $NODE cordoned. No new pods will be scheduled here."

# Step 2: Label the node for network policy targeting
echo "[Step 2] Labeling node as compromised..."
kubectl label node "$NODE" security.incident/status=isolated --overwrite

# Step 3: Drain — evict all pods (except DaemonSets)
echo "[Step 3] Draining node (this may take a while)..."
kubectl drain "$NODE" \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=30 \
  --timeout=120s || {
    echo "WARNING: Drain did not complete cleanly. Check for stuck pods."
    echo "Continuing with isolation..."
  }

# Step 4: Apply network policy to block traffic from remaining pods
echo "[Step 4] Applying isolation network policy..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: node-isolation-${NODE}
  namespace: default
  labels:
    security.incident/node: "${NODE}"
    security.incident/created: "$(date +%Y%m%d-%H%M%S)"
spec:
  podSelector:
    matchLabels:
      kubernetes.io/hostname: "${NODE}"
  policyTypes:
    - Ingress
    - Egress
EOF

echo ""
echo "=== Node $NODE isolated ==="
echo "Next steps:"
echo "  1. Run ./node-isolation/investigate.sh $NODE to collect forensics"
echo "  2. Review audit logs: grep '$NODE' /var/log/kubernetes/audit.log"
echo "  3. After investigation, uncordon with: kubectl uncordon $NODE"
