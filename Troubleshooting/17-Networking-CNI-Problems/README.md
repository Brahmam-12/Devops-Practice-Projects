# Scenario 17: Networking and CNI Problems

## Symptom
- Pods cannot communicate with each other
- Inter-pod traffic works within a node but fails across nodes
- Pod can reach internet but not other pods
- NetworkPolicy blocking unexpected traffic
- CNI pods in kube-system are crashing

---

## 1. Understand the Architecture

```
CNI (Container Network Interface) = the plugin that gives each pod an IP
and routes traffic between pods across nodes.

Common CNIs:
  AWS EKS:    VPC CNI (aws-node DaemonSet) — each pod gets a VPC IP
  Azure AKS:  Azure CNI or Kubenet
  Self-managed: Calico, Cilium, Flannel, Weave

Traffic flows:
  Same node:  Pod-A → veth → bridge → Pod-B (no CNI routing needed)
  Cross-node: Pod-A → veth → node-1 routing table → tunnel/VPC route → node-2 → Pod-B

NetworkPolicy: optional L3/L4 firewall between pods (implemented by CNI)
  Default: all traffic allowed
  With NetworkPolicy: only explicitly allowed traffic flows
```

---

## 2. Troubleshooting Strategy

### Step 1: Confirm it's a pod-to-pod issue

```bash
# Create a debug pod to test connectivity
kubectl run debug --image=busybox --rm -it --restart=Never -n production -- sh

# Inside debug pod:
ping 10.0.1.5          # ping another pod by IP
wget -O- http://myservice:8080/health   # test service connectivity
nslookup myservice     # test DNS

# Get IP of target pod
kubectl get pod myapp-xxx -n production -o wide
# POD IP: 10.0.1.5

# If ping works but HTTP fails → port/app issue, not CNI
# If ping fails → CNI or NetworkPolicy issue
```

---

### Step 2: Check CNI pods are healthy

```bash
# AWS EKS — check aws-node DaemonSet
kubectl get pods -n kube-system | grep aws-node
# aws-node-xxxx  1/1  Running  0  5d ← should be Running on every node

# If aws-node is crashing
kubectl logs -n kube-system <aws-node-pod>
# "Retrying" or auth errors → IAM role missing EC2/VPC permissions

# Azure AKS — check azure-cni or kubenet pods
kubectl get pods -n kube-system | grep azure
kubectl get pods -n kube-system | grep flannel

# Generic — check all kube-system pods
kubectl get pods -n kube-system
# Any CrashLoopBackOff or Error → CNI is broken
```

---

### Step 3: Check NetworkPolicy — is it blocking traffic?

```bash
# List all NetworkPolicies in namespace
kubectl get networkpolicies -n production

# Describe a specific policy
kubectl describe networkpolicy myapp-netpol -n production

# A NetworkPolicy that selects a pod overrides the default "allow all"
# If pod-A has a NetworkPolicy but pod-B is not in its ingress rules → BLOCKED

# Test: temporarily delete the NetworkPolicy to confirm it's the blocker
kubectl delete networkpolicy myapp-netpol -n production
# Does traffic work now? → NetworkPolicy was the problem
# Restore it and fix the rules
```

---

### Step 4: Check VPC routes (cross-node pod traffic)

```bash
# AWS EKS — pod IPs are VPC IPs, must have routes in route table

# Check node has correct annotations for VPC CNI
kubectl describe node <node-name> | grep vpc.amazonaws.com

# Check ENI (Elastic Network Interface) on the node
aws ec2 describe-network-interfaces \
  --filters "Name=attachment.instance-id,Values=i-xxxx"

# If pod has no IP assigned → aws-node hit ENI limit
# Each EC2 instance type has max ENI count and max IPs per ENI
# Solution: use larger instance type or enable prefix delegation
```

---

### Step 5: Check if NetworkPolicy is correct but missing selector

```yaml
# Common mistake: NetworkPolicy selector matches wrong labels
kubectl get pods -n production --show-labels | grep myapp
# myapp-xxx  labels: app=myapp,version=v2

# NetworkPolicy:
spec:
  podSelector:
    matchLabels:
      app: myapp          # correct
      version: v1         # WRONG — pod has version=v2
# → policy doesn't apply to ANY pod (no match) or applies to wrong pods
```

---

## 4. Root Cause + Fix

| Root Cause | Evidence | Fix |
|-----------|----------|-----|
| CNI pod crashing | kube-system pods in error | Fix CNI pod (check IAM, logs) |
| NetworkPolicy too restrictive | Traffic blocked after policy added | Add correct ingress/egress rules |
| ENI limit reached (EKS) | Pods stuck in Pending, no IP assigned | Use larger instance or prefix delegation |
| VPC route missing | Cross-node ping fails | Check route table, subnet associations |
| Label selector mismatch | Policy doesn't match intended pods | Fix labels in NetworkPolicy or pod |

---

## Interview Answer

**Q: "Pods can't communicate across nodes — how do you debug?"**

> "I start by confirming it's a CNI issue and not a DNS or application issue — I run a debug busybox pod and ping the target pod's IP directly. If cross-node ping fails I check the CNI daemonset in kube-system — for EKS that's aws-node. If aws-node is crashing it's usually an IAM issue where the node role is missing EC2 VPC permissions. If CNI is healthy I check NetworkPolicies — if a pod has a NetworkPolicy applied, only explicitly allowed traffic flows, which can accidentally block legitimate cross-pod communication. I temporarily delete the NetworkPolicy to confirm it's the cause, then fix the ingress/egress rules."
