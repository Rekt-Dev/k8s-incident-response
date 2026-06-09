#!/bin/bash
# etcd snapshot backup
# Run on the control plane node (192.168.1.110) as root or with sudo.
# Requires etcdctl v3 and access to the etcd TLS certs.
#
# Kubeadm stores etcd certs at /etc/kubernetes/pki/etcd/
# etcd listens on https://127.0.0.1:2379 by default in kubeadm clusters.
#
# Usage: ./backup.sh [output-directory]
#   Default output: /var/backups/etcd/

set -euo pipefail

BACKUP_DIR="${1:-/var/backups/etcd}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT_FILE="${BACKUP_DIR}/etcd-snapshot-${TIMESTAMP}.db"

ETCD_CACERT="/etc/kubernetes/pki/etcd/ca.crt"
ETCD_CERT="/etc/kubernetes/pki/etcd/healthcheck-client.crt"
ETCD_KEY="/etc/kubernetes/pki/etcd/healthcheck-client.key"
ETCD_ENDPOINT="https://127.0.0.1:2379"

# Verify certs exist
for f in "$ETCD_CACERT" "$ETCD_CERT" "$ETCD_KEY"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: Required cert not found: $f" >&2
    exit 1
  fi
done

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

echo "[$(date)] Starting etcd snapshot backup to ${SNAPSHOT_FILE}"

ETCDCTL_API=3 etcdctl snapshot save "$SNAPSHOT_FILE" \
  --endpoints="$ETCD_ENDPOINT" \
  --cacert="$ETCD_CACERT" \
  --cert="$ETCD_CERT" \
  --key="$ETCD_KEY"

echo "[$(date)] Backup complete. Verifying snapshot..."

# Verify the snapshot is valid
ETCDCTL_API=3 etcdctl snapshot status "$SNAPSHOT_FILE" \
  --write-out=table

echo "[$(date)] Snapshot verified: ${SNAPSHOT_FILE}"
echo "[$(date)] Size: $(du -sh "${SNAPSHOT_FILE}" | cut -f1)"

# Rotate old backups — keep last 7
find "$BACKUP_DIR" -name "etcd-snapshot-*.db" -mtime +7 -delete
echo "[$(date)] Old snapshots cleaned up (kept last 7 days)"
