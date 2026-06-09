# Falco Alert Triage Playbook

Reference for responding to Falco alerts on the homelab cluster. Each section covers a specific alert pattern, what it means, how to verify whether it is a real incident, and what to do about it.

## Shell Spawned in Container

**What it means:** A shell process (`bash`, `sh`, `zsh`) was started inside a container. Legitimate causes include debugging sessions via `kubectl exec` and container entrypoints that use a shell wrapper.

**How to triage:**

```bash
# Check who ran the exec
grep '"verb":"create"' /var/log/kubernetes/audit.log | \
  grep 'pods/exec' | \
  jq '{user: .user.username, pod: .objectRef.name, ns: .objectRef.namespace, time: .requestReceivedTimestamp}'

# Get current state of the pod
kubectl describe pod <pod-name> -n <namespace>

# Check what the shell process did (if still running)
kubectl exec -n <namespace> <pod-name> -- ps auxf
```

**False positive:** Developer ran `kubectl exec -it pod -- /bin/sh` for debugging. Verify via audit log — the exec should be attributed to a known user identity.

**Real incident indicators:**
- exec attributed to a service account, not a human user
- Shell spawned without a corresponding audit log entry (may indicate container escape)
- Shell spawned in a namespace where no developers have exec permissions

**Response:**
1. Immediately run `./node-isolation/isolate-node.sh <node-name>` if the shell origin is unclear
2. Collect the pod's environment: `kubectl exec <pod> -- env`
3. Check for exfiltration: review network connections from the pod's node

---

## Privilege Escalation / Setuid Binary

**What it means:** A setuid binary was executed in a container. If an attacker breaks out of a container, they may use setuid binaries on the host to escalate to root.

**How to triage:**

```bash
# Check the container's security context
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.containers[*].securityContext}'

# Check if the pod is running as root
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.securityContext.runAsUser}'
```

**False positive:** Some containers intentionally use `ping` (which is setuid) for network diagnostics.

**Real incident indicators:**
- Binary is not `ping` or other known-good tools
- Container image is an application image, not a debug/tooling image
- Pod has `privileged: true` or no securityContext restrictions

**Response:**
1. Delete the pod immediately: `kubectl delete pod <pod-name> -n <namespace> --force`
2. Examine the image for embedded malicious binaries: `crictl inspect <container-id>`
3. Review how the pod spec was created — check if anyone modified the deployment

---

## Crypto Miner Detected

**What it means:** A process was detected with signatures matching crypto mining software. This is typically the end goal of container escapes — compute theft.

**This is always a real incident. Treat as critical.**

**Immediate response:**

```bash
# 1. Identify the pod and node
kubectl get pods --all-namespaces -o wide | grep <pod-name>

# 2. Isolate the node immediately
./node-isolation/isolate-node.sh <node-name>

# 3. Preserve evidence before deleting
./node-isolation/investigate.sh <node-name>

# 4. Delete the workload
kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0
```

**Post-incident:**
- Review how the miner was introduced (compromised image, supply chain attack, RCE in app)
- Check Docker Hub / registry for the image — the image itself may be malicious
- Rotate all service account tokens and credentials in the affected namespace
- Audit all other pods using the same image

---

## Kubernetes Service Account Token Read

**What it means:** A container process read the projected service account token. This is normal for any workload that talks to the Kubernetes API. Falco fires when the reading process is unusual.

**How to triage:**

```bash
# Check what the pod is supposed to do — does it legitimately need API access?
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.serviceAccountName}'
kubectl get serviceaccount <sa-name> -n <namespace> -o yaml

# Check what the SA is bound to
kubectl get rolebindings,clusterrolebindings --all-namespaces -o json | \
  jq --arg sa "<sa-name>" --arg ns "<namespace>" \
  '.items[] | select(.subjects[]? | select(.name==$sa and .namespace==$ns))'
```

**False positive:** Any pod that legitimately calls the Kubernetes API (operators, controllers, monitoring agents).

**Real incident indicators:**
- Token read by a process that has no reason to call the API (e.g., your app backend)
- Token read followed by unusual API server calls in the audit log
- Container image has a known RCE vulnerability

**Response:**
1. Check audit log for API calls made using the token after the read
2. If token was used maliciously, rotate it: `kubectl delete secret <token-secret> -n <namespace>`
3. Review and reduce SA permissions if they are broader than needed

---

## Container Access to Host /etc

**What it means:** A container process accessed files in `/etc` on the host via a hostPath volume mount. This should almost never happen in a correctly configured cluster.

**Immediate questions:**
- Is this pod supposed to have a hostPath mount? Check the pod spec.
- If yes, was the access to `/etc` specifically intended?

```bash
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.volumes}'
```

**Real incident indicators:**
- Pod spec shows no hostPath mount but the alert fired (indicates container escape)
- Access to `/etc/shadow`, `/etc/passwd`, `/etc/kubernetes/`

**Response:**
1. If no hostPath mount in spec: immediate node isolation, this may be a container escape
2. If hostPath is present: audit who created the pod with this mount, remove if unnecessary
