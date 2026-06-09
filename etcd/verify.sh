#!/bin/bash
# Verify etcd snapshot integrity and print status
# Run on the control plane node.
# Usage: ./verify.sh [snapshot-file]
#   Default: most recent snapshot in /var/backups/etcd/

set -euo pipefail

BACKUP_DIR="/var/backups/etcd"

if [[ -n "${1:-}" ]]; then
  SNAPSHOT_FILE="$1"
else
  SNAPSHOT_FILE=$(ls -t "${BACKUP_DIR}"/etcd-snapshot-*.db 2>/dev/null | head -1)
  if [[ -z "$SNAPSHOT_FILE" ]]; then
    echo "ERROR: No snapshots found in $BACKUP_DIR" >&2
    exit 1
  fi
fi

echo "Verifying: $SNAPSHOT_FILE"
echo "Modified:  $(stat -c %y "$SNAPSHOT_FILE")"
echo "Size:      $(du -sh "$SNAPSHOT_FILE" | cut -f1)"
echo ""

ETCDCTL_API=3 etcdctl snapshot status "$SNAPSHOT_FILE" --write-out=table

echo ""
echo "Snapshot integrity: OK"
