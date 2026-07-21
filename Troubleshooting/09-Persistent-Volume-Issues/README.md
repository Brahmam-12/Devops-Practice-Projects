# Scenario 09: Persistent Volume Issues

## Symptom
- Pod stuck in `Pending` state with volume error
- Pod stuck in `ContainerCreating` (cannot mount volume)
- `kubectl describe pod` shows: `FailedMount` or `FailedAttachVolume`
- Data missing after pod restart (volume not persisted correctly)
- Read-only filesystem error in running pod

---

## 1. Understand the Architecture

```
Kubernetes Persistent Volumes:

PVC (PersistentVolumeClaim)   ← what the pod requests ("I need 10Gi")
    │
    ▼
PV (PersistentVolume)         ← the actual storage resource
    │
    ▼
Storage Backend               ← AWS EBS, Azure Disk, NFS, Azure Files, etc.

Flow:
  Pod → requests PVC → PVC binds to PV → PV mounts to node → container mounts PV

What can break:
  PVC in Pending  → no PV matches the request (size, storageClass, accessMode)
  Pod stuck       → volume cannot be mounted (node affinity, zone mismatch)
  Data lost       → PVC deleted, or hostPath used instead of PV
  Read-only       → volume mounted read-only, or disk full
```

---

## 2. Troubleshooting Strategy

### Step 1: Check PVC status

```bash
kubectl get pvc -n production

# NAME         STATUS    VOLUME    CAPACITY  ACCESS MODES  STORAGECLASS  AGE
# myapp-pvc    Bound     pv-xxx    10Gi      RWO           gp2           5d  ← OK
# myapp-pvc    Pending   <none>    <none>                  gp2           5m  ← PROBLEM

# If Pending:
kubectl describe pvc myapp-pvc -n production
# Events:
# Warning  ProvisioningFailed: storageclass.storage.k8s.io "gp2" not found
# Warning  ProvisioningFailed: failed to provision volume: InvalidParameterValue: size too large
```

---

### Step 2: Check pod events for mount errors

```bash
kubectl describe pod <pod-name> -n production

# Events:
# Warning FailedAttachVolume: Multi-Attach error: volume is already exclusively attached to node
# Warning FailedMount: Unable to mount volumes: timeout expired waiting for volumes to attach
# Warning FailedMount: MountVolume.SetUp failed: mount failed: executable not found
```

**What each error means:**

| Event | Meaning |
|-------|---------|
| `Multi-Attach error` | EBS volume already attached to another node. Pod rescheduled but old node didn't release. |
| `timeout waiting for volumes to attach` | Volume creation slow (new EBS), or wrong AZ |
| `storageclass not found` | StorageClass name typo, or SC doesn't exist in cluster |
| `volume has no capacity left` | Disk full inside the volume |

---

### Step 3: Zone mismatch — most common EBS issue

```bash
# EBS volumes are zone-specific — a pod in AZ-1b cannot mount an EBS in AZ-1a

# Check which AZ the PV (EBS volume) is in
kubectl describe pv <pv-name> | grep zone
# Labels: topology.kubernetes.io/zone=us-east-1a

# Check which node the pod is scheduled on
kubectl get pod <pod-name> -n production -o wide
# NODE: ip-10-0-2-x.ec2.internal   ← which AZ is this node in?

kubectl describe node ip-10-0-2-x.ec2.internal | grep zone
# Labels: topology.kubernetes.io/zone=us-east-1b   ← DIFFERENT AZ → cannot mount!
```

---

### Step 4: Multi-Attach error (StatefulSet scale-down or rescheduling)

```bash
# Happens when:
# - Old pod on node-1 had volume attached
# - Pod rescheduled to node-2
# - node-1 didn't properly detach the volume
# - node-2 tries to attach but volume "already in use"

# Check the EBS volume state in AWS
aws ec2 describe-volumes --volume-ids vol-xxxxx \
  --query "Volumes[0].Attachments"

# If state: "attached" to old node that no longer runs the pod:
# Force detach from old node
aws ec2 detach-volume --volume-id vol-xxxxx --force

# In Kubernetes — delete the stuck pod to trigger clean reschedule
kubectl delete pod <stuck-pod-name> -n production
```

---

### Step 5: Check if volume is full

```bash
# Inside the pod
kubectl exec <pod-name> -n production -- df -h

# Filesystem      Size  Used Avail Use% Mounted on
# /dev/xvda       10G   9.8G  200M  98% /data   ← 98% full → writes fail → app errors

# Check what's consuming space
kubectl exec <pod-name> -n production -- du -sh /data/* | sort -rh | head -10
```

---

## 4. Root Cause Analysis + Fix

| Root Cause | Evidence | Fix |
|-----------|----------|-----|
| PVC Pending — StorageClass missing | describe PVC: SC not found | Create/fix StorageClass |
| Zone mismatch | PV in AZ-1a, pod on AZ-1b node | Pin pod to correct AZ or use topology-aware provisioning |
| Multi-Attach error | EBS still attached to old node | Force detach from AWS console, delete old pod |
| Disk full | df shows 100% usage | Expand PVC, clean up data, increase volume size |
| PVC deleted | PVC not found | Re-create PVC (data is lost if PV reclaim policy was Delete) |

---

## 5. Fix Commands

```bash
# Expand PVC (StorageClass must support volume expansion)
kubectl patch pvc myapp-pvc -n production \
  --patch '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'

# Check expansion status
kubectl describe pvc myapp-pvc -n production | grep -A 3 Conditions

# Force delete stuck pod
kubectl delete pod <pod-name> -n production --grace-period=0 --force

# Azure Disk — resize disk
az disk update --resource-group myrg --name mydisk --size-gb 50
```

---

## Interview Answer

**Q: "A pod is stuck in ContainerCreating with a volume error — how do you debug?"**

> "I start with kubectl describe pod to read the Events section. Common volume errors are zone mismatch (EBS volume in AZ-1a but pod scheduled to AZ-1b), Multi-Attach error (volume still attached to old node after rescheduling), or the PVC itself is Pending because no PV matches. For zone mismatch I check the topology labels on both the PV and the node the pod landed on. For Multi-Attach I force detach the volume from AWS and delete the stuck pod so it can cleanly reschedule. For a full disk, I check df -h inside the pod and either clean up files or expand the PVC if the StorageClass supports it."
