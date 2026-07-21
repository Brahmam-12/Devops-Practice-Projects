# Scenario 14: Autoscaling Not Working

## Symptom
- CPU/memory is high but new pods/instances are not added
- Traffic dropped but pods/instances are not removed (over-provisioned, wasting money)
- HPA shows correct metrics but doesn't scale
- ASG desired count not increasing despite high load

---

## 1. Understand the Architecture

```
Two layers of autoscaling:

KUBERNETES:
  HPA (Horizontal Pod Autoscaler) → adds/removes PODS
      monitors: CPU, memory, custom metrics
      needs: metrics-server running in cluster
  Cluster Autoscaler → adds/removes NODES
      triggered when: pods are Pending due to insufficient node capacity

AWS:
  Auto Scaling Group → adds/removes EC2 INSTANCES
      trigger: CloudWatch alarms or Target Tracking policy
      needs: correct IAM role, correct metric

Azure:
  VMSS Autoscale → adds/removes VMs
      trigger: Azure Monitor metrics
```

---

## 2. Troubleshooting Strategy

### Step 1: Kubernetes HPA — check current state

```bash
kubectl get hpa -n production

# NAME     REFERENCE           TARGETS       MINPODS  MAXPODS  REPLICAS  AGE
# myapp    Deployment/myapp    85%/70%       2        10       2         5d
#                              ↑CURRENT/TARGET
# Current is 85%, target is 70% → should be scaling up. Why isn't it?

kubectl describe hpa myapp -n production

# Look at:
# AbleToScale: True/False   → can it scale?
# ScalingActive: True/False → is metrics collection working?
# Conditions:
# ScalingLimited: True "the desired count is greater than the maximum pod count"
#   → already at MAX replicas, cannot scale more — increase maxReplicas
# ScalingLimited: True "the current cpu average utilization is lower than target"
#   → metric dropped before scale triggered
```

---

### Step 2: Check if metrics-server is running

```bash
# HPA reads CPU/memory from metrics-server
kubectl get pods -n kube-system | grep metrics-server

# If not running → HPA cannot read metrics → no scaling
kubectl top pods -n production
# Error: metrics not available → metrics-server missing

# Install metrics-server (EKS)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify
kubectl top nodes
kubectl top pods -n production
```

---

### Step 3: Check HPA cannot scale (at min or max)

```bash
kubectl describe hpa myapp -n production | grep -A 5 Conditions

# "the current number of replicas is equal to the desired minimum"
# → traffic dropped, scale-in is blocked by cooldown period (default 5 min)

# "the desired count is greater than the maximum pod count"
# → already at max — fix: increase maxReplicas

kubectl patch hpa myapp -n production \
  --patch '{"spec":{"maxReplicas":20}}'
```

---

### Step 4: Cluster Autoscaler — nodes not added

```bash
# If HPA is scaling up pods but they're Pending:
kubectl get pods -n production | grep Pending
kubectl describe pod <pending-pod> -n production
# Events: 0/3 nodes are available: 3 Insufficient cpu

# Cluster Autoscaler should add a node — check if it's running
kubectl get pods -n kube-system | grep cluster-autoscaler

kubectl logs -n kube-system deployment/cluster-autoscaler | tail -50
# Look for: "Skipping group" or "No candidates for scale up"

# Common issue: ASG max size reached
# Fix: increase max size in ASG
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name eks-node-group-xxx \
  --max-size 20
```

---

### Step 5: AWS ASG — Target Tracking not scaling

```bash
# Check scaling activities
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name my-asg \
  --max-items 10

# Check CloudWatch alarm state
aws cloudwatch describe-alarms \
  --alarm-names my-cpu-alarm \
  --query "MetricAlarms[0].{State:StateValue,Reason:StateReason}"

# If alarm state = INSUFFICIENT_DATA → not enough data points
# If alarm state = OK → metric is below threshold (no scaling needed)
# If alarm state = ALARM → should be scaling — check cooldown

# Check cooldown period
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names my-asg \
  --query "AutoScalingGroups[0].DefaultCooldown"
# Default: 300 seconds (5 min) — if a scale just happened, ASG waits 5 min before next
```

---

## 4. Root Cause + Fix

| Root Cause | Evidence | Fix |
|-----------|----------|-----|
| metrics-server not installed | `kubectl top` fails | Install metrics-server |
| HPA at maxReplicas | Conditions: max count reached | Increase maxReplicas |
| Cooldown period active | Recent scale activity in ASG | Wait, or reduce cooldown |
| ASG max size too low | Cluster Autoscaler logs: max reached | Increase ASG max-size |
| Wrong metric in HPA | Target showing `<unknown>` | Fix metric name, check Prometheus/KEDA |

---

## Interview Answer

**Q: "HPA is configured but pods aren't scaling despite high CPU — how do you debug?"**

> "I start with kubectl describe hpa to read the Conditions section — it tells you exactly why scaling is blocked. Common reasons: metrics-server isn't installed so HPA can't read CPU metrics, the deployment is already at maxReplicas, or a cooldown period is active after a recent scale event. I also check kubectl top pods to confirm metrics are being collected at all. If pods are pending after HPA scales up, the issue moves to the Cluster Autoscaler — I check its logs for why it's not adding nodes, usually because the ASG max size is too low."
