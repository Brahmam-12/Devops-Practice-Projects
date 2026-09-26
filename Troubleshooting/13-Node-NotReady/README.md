# Scenario 13: Node NotReady

## Symptom
- `kubectl get nodes` shows node status: `NotReady`
- Pods on that node are being evicted
- Alert: node is not ready
- New pods not scheduling on the affected node

---

## 1. Understand the Architecture

```
When a node goes NotReady:
  kubelet (agent on the node) stops sending heartbeats to API server
  → API server marks node NotReady after 40 seconds
  → After 5 minutes: pods on node get "Evicted" status
  → Kubernetes reschedules evicted pods to other nodes

Causes:
  Kubelet crashed   → process not running on node
  Node out of memory → kernel OOMKilled kubelet
  Disk full         → kubelet cannot write, crashes
  Network issue     → node isolated, cannot reach API server
  Node crashed      → EC2/VM is down
```

---

## 2. Troubleshooting Strategy

### Step 1: Get node status and conditions

```bash
kubectl get nodes
# NAME           STATUS     ROLES   AGE   VERSION
# node-1         Ready      <none>  5d    v1.28.0
# node-2         NotReady   <none>  5d    v1.28.0   ← problem node

kubectl describe node node-2

# Conditions section:
# Type              Status  Reason
# MemoryPressure    True    KubeletHasSufficientMemory → node is running out of memory
# DiskPressure      True    KubeletHasNoDiskPressure   → disk full
# PIDPressure       True    NodeHasSufficientPID       → too many processes
# Ready             False   KubeletNotReady            → kubelet is down

# Events section:
# Node node-2 status is now: NodeNotReady
```

---

### Step 2: SSH into the node and check kubelet

```bash
# AWS — get node IP
kubectl get node node-2 -o wide

# SSH in
ssh -i key.pem ec2-user@<node-private-ip>

# Check kubelet status
systemctl status kubelet

# Kubelet logs
journalctl -u kubelet -n 100 --no-pager

# Common kubelet errors:
# "failed to run Kubelet: unable to load client CA file"  → cert issue
# "no space left on device"                               → disk full
# "OOMKilled"                                             → kubelet itself OOMKilled
```

---

### Step 3: Check disk and memory on node

```bash
# Disk usage
df -h
# If / or /var is full → kubelet cannot write temp files → crashes

# Find large files
du -sh /* 2>/dev/null | sort -rh | head -10

# Common culprit: Docker/containerd image cache
du -sh /var/lib/docker
du -sh /var/lib/containerd

# Clean up unused images
crictl images | head -20
crictl rmi --prune    # remove unused container images

# Memory
free -m
dmesg | grep -i "out of memory"   # did kernel OOMKill something?
```

---

### Step 4: AWS — Check EC2 instance health

```bash
# Is the EC2 actually running?
aws ec2 describe-instances \
  --filters "Name=private-ip-address,Values=10.0.x.x" \
  --query "Reservations[0].Instances[0].{State:State.Name,HealthStatus:State.Name}"

# Check system status checks
aws ec2 describe-instance-status \
  --instance-ids i-xxxx \
  --query "InstanceStatuses[0].{System:SystemStatus.Status,Instance:InstanceStatus.Status}"

# If system check failed → underlying hardware issue
# Action: terminate instance, ASG will replace it
aws ec2 terminate-instances --instance-ids i-xxxx
```

---

### Step 5: Azure — Check VM health

```
Portal → Virtual Machine → left menu → Diagnose and solve problems
       → Check VM status (Running / Stopped / Deallocated)

# Or:
az vm get-instance-view \
  --resource-group myrg \
  --name mynode \
  --query "instanceView.statuses"
```

---

## 4. Root Cause + Fix

| Root Cause | Evidence | Fix |
|-----------|----------|-----|
| Kubelet crashed | `systemctl status kubelet` shows failed | `systemctl restart kubelet` |
| Disk full | `df -h` shows 100% | Clean images: `crictl rmi --prune` |
| Node OOMKilled | `dmesg` shows OOMKill | Add memory to ASG launch template |
| Network isolated | Cannot SSH to node | Check SG, reboot VM, replace node |
| EC2 system check failed | AWS system status failed | Terminate + replace (ASG auto-replaces) |

---

## 5. Fix Commands

```bash
# Restart kubelet
systemctl restart kubelet
systemctl status kubelet

# Drain node before maintenance (moves pods away gracefully)
kubectl drain node-2 --ignore-daemonsets --delete-emptydir-data

# After fix — uncordon to allow scheduling again
kubectl uncordon node-2

# If node needs to be replaced — terminate and let ASG replace
aws ec2 terminate-instances --instance-ids i-xxxx
```

---

## Interview Answer

**Q: "A Kubernetes node shows NotReady — how do you investigate?"**

> "I start with kubectl describe node to see the Conditions — MemoryPressure, DiskPressure, or just the Ready condition being False. Then I SSH into the node and check kubelet status with systemctl status kubelet and journalctl for logs. Disk full is a common cause — containerd image cache fills up over time. I clean up unused images with crictl rmi --prune. If kubelet is crashing due to OOM I check dmesg for OOMKill events. For AWS nodes that fail hardware checks, I drain the node and terminate the EC2 — the Auto Scaling Group replaces it automatically. I always drain before replacing to move pods gracefully."
