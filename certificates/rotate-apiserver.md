# API Server Certificate Rotation

Procedure for renewing Kubernetes certificates before expiry using `kubeadm certs renew`. Tested on kubeadm-managed cluster with Kubernetes v1.35.x.

**Before you start:** Check the current expiry dates.

```bash
kubeadm certs check-expiration
```

## Renew All Certificates at Once

The simplest approach for a homelab — renews all kubeadm-managed certificates:

```bash
# On control plane node (192.168.1.110) as root
kubeadm certs renew all
```

After renewal, the control plane components must be restarted to pick up the new certificates. The fastest way is to restart the static pods:

```bash
# Move manifests out, wait for pods to stop, move back
MANIFESTS="/etc/kubernetes/manifests"
TEMP="/tmp/k8s-manifests"
mkdir -p $TEMP

mv $MANIFESTS/kube-apiserver.yaml $TEMP/
mv $MANIFESTS/kube-controller-manager.yaml $TEMP/
mv $MANIFESTS/kube-scheduler.yaml $TEMP/

sleep 20

mv $TEMP/*.yaml $MANIFESTS/

# Wait for API server to come back
sleep 30
kubectl get nodes
```

## Renew Individual Certificates

If you only need to renew a specific certificate:

```bash
# List available certificates
kubeadm certs renew --help

# Renew only the apiserver cert
kubeadm certs renew apiserver

# Renew only the front-proxy cert
kubeadm certs renew front-proxy-client
```

## Update Kubeconfig Files

After renewing, the admin kubeconfig also needs to be regenerated:

```bash
# Regenerate admin.conf
kubeadm init phase kubeconfig admin

# Regenerate kubelet.conf (needed on each node)
kubeadm init phase kubeconfig kubelet

# Copy updated kubeconfig
cp /etc/kubernetes/admin.conf ~/.kube/config
```

## Verify Renewal

```bash
kubeadm certs check-expiration

# Confirm API server is responding
kubectl get nodes
kubectl get pods -A | head -20
```

## Gotchas

**etcd certificates are separate.** `kubeadm certs renew all` includes etcd certificates, but etcd must also be restarted separately if you renew only etcd certs.

**Worker node certs.** Worker nodes have their own kubelet client certificates, which are typically auto-rotated by kubelet (RotateKubeletClientCertificate is enabled by default in kubeadm clusters). Check with:

```bash
# On a worker node
openssl x509 -noout -enddate -in /var/lib/kubelet/pki/kubelet-client-current.pem
```

**Backup before renewal.** Take an etcd snapshot before renewing certificates in case the renewal process leaves the cluster in a broken state.

```bash
./etcd/backup.sh
```

**CA certificates expire in 10 years.** The `kubeadm certs check-expiration` output distinguishes CA certs (10 year expiry) from leaf certs (1 year). CA rotation is a much more involved process and not covered here.
