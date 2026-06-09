# k8s-incident-response

Operational runbooks and scripts for incident response on a kubeadm cluster. These were originally written as CKS exam preparation and evolved into actual tools used on the homelab cluster after passing the exam. The exam tests knowledge of etcd backup/restore, certificate management, and runtime security — this repo makes that knowledge immediately actionable.

## Cluster Context

- **Nodes:** k8s (control plane, 192.168.1.110), k8s1, k8s2
- **Kubernetes version:** v1.35.x (kubeadm-managed)
- **Runtime security:** Falco
- **CNI:** Calico

## Repository Structure

```
etcd/
  backup.sh               Snapshot save with cert paths pre-configured for this cluster
  restore.sh              Full restore procedure including control plane restart
  verify.sh               Verify snapshot integrity
certificates/
  check-expiry.sh         Check all cert expiry dates, flag <30 and <90 day warnings
  rotate-apiserver.md     Step-by-step cert rotation procedure
node-isolation/
  isolate-node.sh         Cordon, drain, and network policy isolate a suspected node
  investigate.sh          Collect forensics from the API side before direct node access
falco/
  custom-rules.yaml       Falco rules tuned for this cluster's workload patterns
  triage-playbook.md      Response guide for each Falco alert category
rbac-audit/
  audit-bindings.sh       Full RBAC audit — overprivileged bindings, wildcard roles
  find-clusteradmin.sh    Find all principals with cluster-admin access
```

## Quick Reference

### etcd Backup

```bash
# Take a snapshot now
sudo ./etcd/backup.sh

# Verify the latest snapshot
sudo ./etcd/verify.sh

# List existing backups
ls -lh /var/backups/etcd/
```

### Check Certificate Expiry

```bash
sudo ./certificates/check-expiry.sh
# Or use kubeadm directly:
sudo kubeadm certs check-expiration
```

### Isolate a Compromised Node

```bash
# Cordon, drain, and network-isolate
./node-isolation/isolate-node.sh k8s1

# Collect forensics
./node-isolation/investigate.sh k8s1
```

### RBAC Audit

```bash
# Full audit
./rbac-audit/audit-bindings.sh

# Find all cluster-admin access
./rbac-audit/find-clusteradmin.sh
```

## etcd Backup Strategy

Kubeadm etcd stores all cluster state: Secrets, ConfigMaps, Deployments, RBAC policies, everything. Without a working etcd backup, a control plane failure means rebuilding the entire cluster from scratch.

The backup script uses `etcdctl snapshot save` with the kubeadm-managed certificates at `/etc/kubernetes/pki/etcd/`. The snapshot is a point-in-time copy of the entire key-value store.

**Recommended:** Run `backup.sh` on a cron job daily. Store backups off-node (NFS, S3-compatible storage, etc.). A backup on the same disk as etcd does not help if the disk fails.

```bash
# cron example (as root on control plane)
0 2 * * * /opt/k8s-incident-response/etcd/backup.sh /mnt/nfs-backup/etcd >> /var/log/etcd-backup.log 2>&1
```

**Restore time:** The full restore procedure (stop components, restore, restart) takes approximately 3-5 minutes on this cluster. Practice it before you need it — the CKS exam tests this under time pressure.

## Certificate Management

Kubeadm-managed certificates expire after 1 year by default (CA certificates expire after 10 years). On a homelab cluster that's been running for more than a year without a kubeadm upgrade, all leaf certificates may be expired.

`kubeadm upgrade` automatically renews certificates as part of the upgrade process. If you're not upgrading, run `kubeadm certs renew all` and restart the control plane components annually.

Worker node kubelet certificates auto-rotate by default (`RotateKubeletClientCertificate` is enabled). Verify this is happening:

```bash
# On a worker node
ls -la /var/lib/kubelet/pki/
# kubelet-client-current.pem should have a recent modification date
```

## Falco Setup

Falco is installed as a DaemonSet on this cluster:

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set driver.kind=modern_ebpf \
  --set falco.grpc.enabled=true \
  --set falco.grpcOutput.enabled=true
```

Custom rules go in `/etc/falco/rules.d/` on each node, or via the Helm chart's `customRules` values. The `custom-rules.yaml` in this repo can be mounted via a ConfigMap:

```bash
kubectl create configmap falco-custom-rules \
  --from-file=custom_rules.yaml=falco/custom-rules.yaml \
  -n falco
```

## Lessons Learned

**The CKS exam etcd restore task is the most time-sensitive.** Practicing the full procedure — stop API server, restore, restart, verify — under a time limit is the best preparation. On this cluster, the full procedure takes 4 minutes from clean state.

**Falco fires on legitimate kubectl exec constantly.** The first week after installing Falco produced hundreds of alerts for normal developer debugging. Tuning the exception lists in `custom-rules.yaml` to match actual usage patterns took about a week.

**RBAC audits reveal drift.** Running `audit-bindings.sh` on this cluster after 6 months of operation revealed 3 service accounts with broader permissions than originally intended — left over from testing that never got cleaned up. Regular RBAC audits are worth the time.

**Draining a node during an incident may be wrong.** If a pod is actively doing something suspicious and you need to capture what it's doing, draining moves it elsewhere and you lose the runtime state. Consider isolating at the network layer first, then investigate before draining.

## Related Repositories

- [k8s-security-hardening](https://github.com/Rekt-Dev/k8s-security-hardening) — preventive controls this playbook responds around
- [k8s-production-patterns](https://github.com/Rekt-Dev/k8s-production-patterns) — the cluster workloads being protected
