#!/bin/bash
# Check expiry dates for all Kubernetes certificates managed by kubeadm
# Run on the control plane node.
# Certificates expire 1 year after cluster creation by default (kubeadm).
# The CA certificates expire 10 years.
#
# kubeadm provides a built-in command for this:
#   kubeadm certs check-expiration
# This script adds custom checks for certs kubeadm doesn't track.

set -euo pipefail

echo "=== Kubernetes Certificate Expiry Check ==="
echo "Date: $(date)"
echo ""

echo "--- kubeadm-managed certificates ---"
kubeadm certs check-expiration

echo ""
echo "--- Raw cert details (openssl) ---"

CERT_PATHS=(
  "/etc/kubernetes/pki/apiserver.crt"
  "/etc/kubernetes/pki/apiserver-etcd-client.crt"
  "/etc/kubernetes/pki/apiserver-kubelet-client.crt"
  "/etc/kubernetes/pki/front-proxy-client.crt"
  "/etc/kubernetes/pki/etcd/server.crt"
  "/etc/kubernetes/pki/etcd/peer.crt"
  "/etc/kubernetes/pki/etcd/healthcheck-client.crt"
)

for cert in "${CERT_PATHS[@]}"; do
  if [[ -f "$cert" ]]; then
    EXPIRY=$(openssl x509 -noout -enddate -in "$cert" 2>/dev/null | cut -d= -f2)
    SUBJECT=$(openssl x509 -noout -subject -in "$cert" 2>/dev/null | sed 's/subject= *//')
    # Check days remaining
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$EXPIRY" +%s 2>/dev/null)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

    if [[ $DAYS_LEFT -lt 30 ]]; then
      STATUS="URGENT - expires in ${DAYS_LEFT} days"
    elif [[ $DAYS_LEFT -lt 90 ]]; then
      STATUS="WARNING - expires in ${DAYS_LEFT} days"
    else
      STATUS="OK - expires in ${DAYS_LEFT} days"
    fi

    echo "[$STATUS] $(basename $cert)"
    echo "  Subject: $SUBJECT"
    echo "  Expiry:  $EXPIRY"
    echo ""
  fi
done

echo "--- Kubeconfig cert expiry ---"
for kubeconfig in /etc/kubernetes/*.conf; do
  CERT=$(grep "client-certificate-data" "$kubeconfig" 2>/dev/null | awk '{print $2}' | base64 -d 2>/dev/null)
  if [[ -n "$CERT" ]]; then
    EXPIRY=$(echo "$CERT" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    echo "$(basename $kubeconfig): expires $EXPIRY"
  fi
done
