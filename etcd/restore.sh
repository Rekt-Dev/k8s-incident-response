#!/bin/bash
# etcd snapshot restore procedure
# Run on the control plane node as root.
# This procedure restores from a snapshot and restarts the cluster.
#
# WARNING: This will replace all cluster state with the snapshot.
# All changes made after the snapshot was taken will be lost.
#
# Usage: ./restore.sh <snapshot-file>

set -euo pipefail

SNAPSHOT_FILE="${1:-}"

if [[ -z "$SNAPSHOT_FILE" ]]; then
  echo "Usage: $0 <snapshot-file>"
  echo "Example: $0 /var/backups/etcd/etcd-snapshot-20260501-120000.db"
  exit 1
fi

if [[ ! -f "$SNAPSHOT_FILE" ]]; then
  echo "ERROR: Snapshot file not found: $SNAPSHOT_FILE" >&2
  exit 1
fi

ETCD_CACERT="/etc/kubernetes/pki/etcd/ca.crt"
ETCD_CERT="/etc/kubernetes/pki/etcd/server.crt"
ETCD_KEY="/etc/kubernetes/pki/etcd/server.key"
RESTORE_DIR="/var/lib/etcd-restore"
ETCD_DATA_DIR="/var/lib/etcd"

echo "=== etcd RESTORE PROCEDURE ==="
echo "Snapshot: $SNAPSHOT_FILE"
echo "This will REPLACE all cluster data. You have 10 seconds to abort (Ctrl+C)..."
sleep 10

# Step 1: Stop API server and etcd by moving static pod manifests
echo "[Step 1] Stopping control plane components..."
mkdir -p /tmp/k8s-manifests-backup
mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/k8s-manifests-backup/ 2>/dev/null || true
mv /etc/kubernetes/manifests/etcd.yaml /tmp/k8s-manifests-backup/ 2>/dev/null || true
mv /etc/kubernetes/manifests/kube-controller-manager.yaml /tmp/k8s-manifests-backup/ 2>/dev/null || true
mv /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/k8s-manifests-backup/ 2>/dev/null || true

# Wait for components to stop (kubelet removes them)
echo "[Step 1] Waiting 30s for components to stop..."
sleep 30

# Verify etcd is stopped
if pgrep etcd > /dev/null 2>&1; then
  echo "WARNING: etcd still running. Waiting 20 more seconds..."
  sleep 20
fi

# Step 2: Backup existing data directory
echo "[Step 2] Backing up existing etcd data..."
if [[ -d "$ETCD_DATA_DIR" ]]; then
  mv "$ETCD_DATA_DIR" "${ETCD_DATA_DIR}.bak.$(date +%Y%m%d-%H%M%S)"
fi

# Step 3: Restore snapshot
echo "[Step 3] Restoring snapshot..."
ETCDCTL_API=3 etcdctl snapshot restore "$SNAPSHOT_FILE" \
  --data-dir="$ETCD_DATA_DIR" \
  --cacert="$ETCD_CACERT" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY" \
  --name="$(hostname)" \
  --initial-cluster="$(hostname)=https://127.0.0.1:2380" \
  --initial-cluster-token="etcd-cluster-1" \
  --initial-advertise-peer-urls="https://127.0.0.1:2380"

echo "[Step 3] Snapshot restored to $ETCD_DATA_DIR"

# Step 4: Restore static pod manifests
echo "[Step 4] Restoring control plane manifests..."
mv /tmp/k8s-manifests-backup/*.yaml /etc/kubernetes/manifests/

echo "[Step 4] Waiting 60s for control plane to start..."
sleep 60

# Step 5: Verify cluster is healthy
echo "[Step 5] Verifying cluster health..."
kubectl get nodes 2>/dev/null || echo "kubectl not responding yet — wait longer and retry"

echo "=== RESTORE COMPLETE ==="
echo "Verify cluster health with: kubectl get nodes && kubectl get pods -A"
