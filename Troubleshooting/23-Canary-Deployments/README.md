# Scenario 23: Canary Deployments

## What Is Canary?

```
Canary = send a small % of real traffic to new version, watch metrics, gradually roll out.
Named after "canary in a coal mine" — if canary dies, you know danger is there.

Blue-Green:  100% → 0% switch (binary, fast)
Canary:      5% → 25% → 50% → 100% (gradual, safer for risky changes)

When to use Canary vs Blue-Green:
  Canary → risky changes, new features, DB migrations, performance-sensitive
  Blue-Green → confident changes, simple deployments, fast rollout needed
```

---

## Kubernetes Implementation

### Method 1: Replica-based Canary (simple, approximate %)

```bash
# Current: 10 replicas of v1 (stable)
# Canary: add 1 replica of v2 → ~9% of traffic goes to v2

# Stable deployment (v1) — already running
kubectl get deployment myapp-stable -n production
# replicas: 10

# Create canary deployment (v2) with 1 replica
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-canary
  namespace: production
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
      track: canary
  template:
    metadata:
      labels:
        app: myapp   # ← same label → Service routes to this too
        track: canary
    spec:
      containers:
      - name: myapp
        image: myapp:v2
EOF

# Service selects app=myapp → routes to BOTH stable (10) and canary (1)
# Ratio: 10:1 → ~9% to canary, ~91% to stable

# Monitor canary metrics (error rate, latency)
# If good → increase canary replicas, decrease stable
kubectl scale deployment myapp-canary -n production --replicas=3
kubectl scale deployment myapp-stable -n production --replicas=8

# Continue until fully canary
kubectl scale deployment myapp-canary -n production --replicas=10
kubectl delete deployment myapp-stable -n production
```

---

### Method 2: Nginx Ingress Canary (precise % control)

```yaml
# Stable Ingress (existing)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-stable
  namespace: production
spec:
  rules:
  - host: app.company.com
    http:
      paths:
      - path: /
        backend:
          service:
            name: myapp-stable-svc
            port:
              number: 80

---
# Canary Ingress (new — 10% of traffic)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-canary
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "10"   # 10% to canary
spec:
  rules:
  - host: app.company.com
    http:
      paths:
      - path: /
        backend:
          service:
            name: myapp-canary-svc
            port:
              number: 80
```

```bash
# Deploy canary Ingress
kubectl apply -f canary-ingress.yaml

# Verify traffic split
# Watch error rates in Grafana for both stable and canary

# Increase canary weight over time
kubectl patch ingress myapp-canary -n production \
  --patch '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/canary-weight":"25"}}}'

# Gradually increase: 10% → 25% → 50% → 75% → 100%

# When 100% and stable — delete stable and remove canary annotation
kubectl patch ingress myapp-canary -n production \
  --patch '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/canary":"false"}}}'
```

---

## AWS Implementation — Weighted Target Groups

```bash
# Split traffic between two Target Groups by weight

aws elbv2 modify-listener \
  --listener-arn arn:... \
  --default-actions '[
    {
      "Type": "forward",
      "ForwardConfig": {
        "TargetGroups": [
          {"TargetGroupArn": "arn:...stable-tg...", "Weight": 90},
          {"TargetGroupArn": "arn:...canary-tg...", "Weight": 10}
        ],
        "StickinessConfig": {"Enabled": false}
      }
    }
  ]'

# Adjust weights as canary proves stable
# 90/10 → 75/25 → 50/50 → 0/100
# Final: remove stable TG from action
```

---

## Azure Implementation — Traffic Manager / Front Door

```bash
# Azure Front Door supports weighted routing

az network front-door load-balancing create \
  --resource-group myrg \
  --front-door-name myfrontdoor \
  --name lb-policy \
  --sample-size 4 \
  --successful-samples-required 2

# Origin group — stable backend
az network front-door origin create \
  --resource-group myrg \
  --front-door-name myfrontdoor \
  --origin-group-name stable-origins \
  --host-name stable.azurewebsites.net \
  --priority 1 \
  --weight 90

# Origin — canary backend
az network front-door origin create \
  --resource-group myrg \
  --front-door-name myfrontdoor \
  --origin-group-name canary-origins \
  --host-name canary.azurewebsites.net \
  --priority 1 \
  --weight 10
```

---

## Monitoring During Canary

```bash
# Key metrics to watch — compare stable vs canary:
# Error rate: canary should not have higher error rate than stable
# P99 latency: canary should not be significantly slower
# Business metrics: conversion rate, user actions (if instrumented)

# Prometheus — compare error rates
rate(http_requests_total{version="canary",status=~"5.."}[5m])
  /
rate(http_requests_total{version="canary"}[5m])
# vs
rate(http_requests_total{version="stable",status=~"5.."}[5m])
  /
rate(http_requests_total{version="stable"}[5m])
```

---

## Rollback

```bash
# Kubernetes Nginx Ingress — set canary weight to 0 (instant rollback)
kubectl patch ingress myapp-canary -n production \
  --patch '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/canary-weight":"0"}}}'

# Delete canary deployment
kubectl delete deployment myapp-canary -n production

# AWS ALB — remove canary target group weight
aws elbv2 modify-listener \
  --listener-arn arn:... \
  --default-actions '[{"Type":"forward","TargetGroupArn":"arn:...stable-tg..."}]'
```

---

## Interview Answer

**Q: "How do you do a canary deployment in Kubernetes?"**

> "I run two deployments — stable with the current version and canary with the new version — both with the same app label so the Service routes to both. By controlling replica counts (10 stable, 1 canary) I get approximately 9% of traffic to canary. For precise percentage control I use Nginx Ingress annotations with canary-weight set to 10, which gives exactly 10% to the canary. I watch error rates and latency for both versions in Grafana side by side. If canary metrics are healthy I gradually increase the weight over 30 minutes. If error rate spikes I set canary weight to 0 — instant rollback. The canary approach is better than blue-green for risky changes because you catch problems when only 10% of users are affected, not 100%."
