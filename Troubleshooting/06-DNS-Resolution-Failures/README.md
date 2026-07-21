# Scenario 06: DNS Resolution Failures

## Symptom
- App cannot connect to a service by hostname (but IP works)
- `nslookup` or `dig` returns NXDOMAIN or SERVFAIL
- Kubernetes pods cannot reach services by service name
- "temporary failure in name resolution" in logs
- New deployment worked in staging but DNS fails in production

---

## 1. Understand the Architecture

```
DNS resolution layers in cloud:

PUBLIC DNS:
  User types api.company.com
  → OS DNS resolver → ISP DNS → Route 53 / Azure DNS
  → returns IP of ALB / App Gateway
  → user connects

INTERNAL DNS (within VPC/VNet):
  EC2 instance → needs to reach db.internal
  → VPC DNS resolver (169.254.169.253 in AWS)
  → Returns private IP of RDS

KUBERNETES DNS:
  Pod → needs to reach myservice
  → CoreDNS (runs as pods in kube-system)
  → Returns ClusterIP of Kubernetes Service
  → Pod connects to service
```

---

## 2. Troubleshooting Strategy

### Step 1: Confirm DNS is the problem, not the app

```bash
# Is it a DNS issue or a network issue?
# Test with hostname
curl -v https://api.company.com

# Test with IP directly (skip DNS)
curl -v https://203.0.113.45 -H "Host: api.company.com"

# If IP works but hostname fails → DNS problem
# If both fail → network/firewall problem (not DNS)
```

---

### Step 2: Run DNS lookup directly

```bash
# Basic lookup
nslookup api.company.com
dig api.company.com

# Specify a particular DNS server
dig @8.8.8.8 api.company.com          # test against Google DNS
dig @169.254.169.253 api.company.com  # test against AWS VPC DNS

# Check NXDOMAIN vs SERVFAIL
# NXDOMAIN → domain does not exist (typo, record deleted, wrong zone)
# SERVFAIL  → DNS server exists but can't answer (internal DNS error)
# TIMEOUT   → cannot reach DNS server (firewall, wrong DNS IP)
```

---

### Step 3: AWS — Check Route 53 records

```bash
# List all records in hosted zone
aws route53 list-resource-record-sets \
  --hosted-zone-id Z123456 \
  --query "ResourceRecordSets[?Name=='api.company.com.']"

# Check if A record or CNAME points to correct ALB
# Common mistake: CNAME points to old ALB that was deleted

# Check hosted zone association with VPC (private zones)
aws route53 get-hosted-zone --id Z123456 \
  --query "VPCs"
# If your EC2 is in a VPC not listed here → private zone doesn't resolve there
```

---

### Step 4: Azure — Check Azure DNS

```
Portal → DNS Zones → select your zone → Records
       → find the A record or CNAME for your service
       → check it points to correct IP / FQDN

# Check if DNS zone is linked to VNet (private zone)
Portal → Private DNS zones → Virtual network links
       → if your VM's VNet is not linked → VMs in that VNet cannot resolve

az network private-dns zone show \
  --resource-group myrg \
  --name privatelink.database.windows.net

az network private-dns link vnet list \
  --resource-group myrg \
  --zone-name privatelink.database.windows.net
```

---

### Step 5: Kubernetes — Debug CoreDNS

```bash
# Step 1: Test DNS from inside a pod
kubectl run dns-test --image=busybox --rm -it --restart=Never -- sh
# Inside pod:
nslookup myservice                          # service in same namespace
nslookup myservice.production               # service in different namespace
nslookup myservice.production.svc.cluster.local  # fully qualified
nslookup google.com                         # external DNS (tests egress)
exit

# Step 2: Check CoreDNS pods are running
kubectl get pods -n kube-system | grep coredns
# coredns-xxxxx  1/1  Running  0  5d  ← both should be Running

# Step 3: Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns
# Error: SERVFAIL → CoreDNS cannot resolve (upstream issue, ConfigMap wrong)
# Error: NXDOMAIN → record genuinely doesn't exist

# Step 4: Check CoreDNS ConfigMap
kubectl get configmap coredns -n kube-system -o yaml
# Look at 'forward' section — where does CoreDNS forward external DNS queries?
# forward . /etc/resolv.conf → uses node's DNS
# forward . 8.8.8.8         → uses Google DNS
```

---

### Step 6: Check if the Service exists in Kubernetes

```bash
# A pod says "myservice" not found — does the Service actually exist?
kubectl get services -n production

# Check the service name matches exactly (case sensitive)
kubectl get svc myservice -n production

# Check endpoints — does the service have pods behind it?
kubectl get endpoints myservice -n production
# If <none> → service has no matching pods (selector mismatch)

# Check selector matches pod labels
kubectl describe svc myservice -n production | grep Selector
kubectl get pods -n production --show-labels | grep app=myapp
```

---

## 4. Root Cause Analysis + Fix

| Root Cause | Evidence | Fix |
|-----------|----------|-----|
| DNS record deleted | `dig` returns NXDOMAIN | Recreate the A/CNAME record |
| Private zone not linked to VNet | Azure DNS not resolving in VM | Add VNet link to private DNS zone |
| Route 53 private zone not associated | VPC DNS returns NXDOMAIN for internal | Associate private zone with VPC |
| CoreDNS pods down | `kubectl get pods -n kube-system` shows 0/1 | Fix CoreDNS pods |
| Service name typo | `kubectl get svc` shows different name | Fix the service name in app config |
| Selector mismatch | `kubectl get endpoints` shows none | Fix pod labels or service selector |
| DNS propagation delay | Works on some machines, not others | Wait (TTL) or reduce TTL for future |

---

## 5. Fixes

```bash
# Kubernetes — restart CoreDNS
kubectl rollout restart deployment coredns -n kube-system

# Kubernetes — fix service selector
kubectl patch service myservice -n production \
  --patch '{"spec":{"selector":{"app":"myapp","version":"v2"}}}'

# AWS — add missing Route 53 record
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123456 \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "api.company.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z35SXDOTRQ7X7K",
          "DNSName": "my-alb-123.us-east-1.elb.amazonaws.com",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

---

## Interview Answer

**Q: "Pod cannot connect to another service by name — how do you debug?"**

> "I first confirm it's a DNS issue and not a network issue by testing with an IP directly. Then I exec into the pod and run nslookup for the service name — Kubernetes services resolve by their short name within the same namespace, or fully qualified as service.namespace.svc.cluster.local. If the lookup fails, I check if CoreDNS pods are healthy in kube-system. If the lookup succeeds but connection fails, it's not DNS — it's a network policy or firewall issue. A common mistake I've seen is a selector mismatch between the Service and the pods — kubectl get endpoints shows none, meaning the service has no backing pods to route to."
