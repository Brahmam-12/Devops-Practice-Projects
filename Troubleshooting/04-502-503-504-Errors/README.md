# Scenario 04: 502 / 503 / 504 Errors

## Symptom
- Users see browser error pages: 502 Bad Gateway, 503 Service Unavailable, 504 Gateway Timeout
- These come from the Load Balancer or Ingress — not from your app
- Alert fires: HTTP 5xx error rate high

---

## 1. Understand the Architecture

```
These errors mean the LOAD BALANCER OR INGRESS received the request
but could not get a valid response from the backend.

The LB/Ingress generates the error code — your app did NOT return it directly.

502 Bad Gateway         → LB got a response from backend but it was invalid/garbled
503 Service Unavailable → LB has no healthy backends to send traffic to
504 Gateway Timeout     → LB connected to backend but backend took too long to respond
```

**Request flow:**
```
Client → DNS → Load Balancer/Ingress → (502/503/504 generated here) → Backend
                                        ↑
                               These errors happen here
```

---

## 2. The Difference Between 502, 503, 504

| Code | Name | What happened | First place to check |
|------|------|--------------|---------------------|
| **502** | Bad Gateway | LB reached backend but got garbage/invalid response | App crashing mid-response, wrong protocol |
| **503** | Service Unavailable | LB has NO healthy backends (all instances down or pool empty) | Target group health, pod readiness |
| **504** | Gateway Timeout | LB reached backend but it didn't respond within the timeout | App hanging, DB slow queries, overloaded |

---

## 3. Troubleshooting Strategy

### For 503 — No healthy backends

**Step 1: Check target health immediately**
```bash
# AWS
aws elbv2 describe-target-health --target-group-arn arn:...

# If all targets show "unhealthy" → that's your 503
# Reason codes:
# Target.FailedHealthChecks → app down, health check failing (→ see Scenario 03)
# Target.DeregistrationInProgress → deploy in progress, targets draining
# Elb.InitialHealthChecking → newly registered targets, wait for health check to pass
```

**Kubernetes:**
```bash
kubectl get endpoints myapp-service -n production
# If ENDPOINTS shows <none> → no pods are passing readiness probe
# If ENDPOINTS shows 10.0.1.5:8080 → pods are ready

kubectl get pods -n production
# Check READY column — 0/1 means readiness failing
```

---

### For 502 — Bad Gateway

**Step 1: Check app logs for crash during request**
```bash
# Check logs for errors during request handling
kubectl logs <pod-name> -n production --tail=100
# Look for: panic, segfault, connection reset, broken pipe

# On EC2
tail -100 /var/log/nginx/error.log
tail -100 /var/log/myapp/error.log
```

**Step 2: Check if backend is using wrong protocol**
```bash
# 502 often happens when:
# LB sends HTTP but app expects HTTPS (or vice versa)
# LB sends HTTP/1.1 but app only speaks HTTP/2
# Check the LB listener and target group protocol

aws elbv2 describe-target-groups --target-group-arns arn:...
# Protocol: HTTP vs HTTPS — does it match what your app expects?
```

**Step 3: Check Nginx/proxy upstream errors (if using reverse proxy)**
```bash
tail -f /var/log/nginx/error.log
# upstream prematurely closed connection → backend crashed during request
# upstream timed out → backend too slow (this causes 504, not 502)
# no live upstreams while connecting to upstream → all backends down (causes 503)
```

---

### For 504 — Gateway Timeout

**Step 1: Check LB timeout settings**
**What:** Is the LB timeout shorter than the time your app needs to respond?
**Why:** If app takes 70s to respond but LB timeout is 60s → 504 every time.

```bash
# AWS — check ALB idle timeout
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn arn:aws:elasticloadbalancing:... \
  --query "Attributes[?Key=='idle_timeout.timeout_seconds']"

# Default: 60 seconds
# If your app takes longer → increase timeout or fix the slow operation
```

**Azure:**
```
Portal → Load Balancer → Load balancing rules → select rule
       → TCP idle timeout (minutes): default 4 minutes
```

**Step 2: Check app response time**
**What:** How long does the app actually take to respond?
**Why:** Confirms if the issue is the timeout config or the app being genuinely slow.

```bash
# Time the response
time curl -v http://10.0.3.x:8080/api/slow-endpoint

# Or check application metrics
kubectl top pods -n production

# Check if specific endpoints are slow
kubectl logs <pod-name> -n production | grep "slow\|timeout\|duration"
```

**Step 3: Check database — slow queries are the most common 504 cause**
```bash
# On EC2 — check if DB connections are stacking up
netstat -an | grep ESTABLISHED | grep 5432   # PostgreSQL
netstat -an | grep ESTABLISHED | grep 3306   # MySQL

# Kubernetes — exec into pod and check DB response time
kubectl exec <pod-name> -n production -- \
  time psql -h db-host -U user -c "SELECT 1"

# AWS RDS — check slow query log in RDS Console:
# RDS → Databases → select DB → Logs & events → slow query log

# Azure SQL — check Query Performance Insight:
# Portal → Azure SQL → Query Performance Insight
```

**Step 4: Check if the app is overloaded (too many requests)**
```bash
# Kubernetes — check CPU/memory
kubectl top pods -n production
kubectl top nodes

# AWS — check EC2 CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=i-xxxxx \
  --start-time 2026-06-26T09:00:00 \
  --end-time 2026-06-26T10:00:00 \
  --period 60 \
  --statistics Average
```

---

## 4. Root Cause Analysis + Fix

| Error | Root Cause | Evidence | Fix |
|-------|-----------|----------|-----|
| **503** | All instances unhealthy | Target health: all fail | Fix app crash / health check (→ Scenarios 01, 03) |
| **503** | Deploy draining all targets | Targets "draining" | Wait, or fix deploy strategy |
| **503** | Scale-in removed all instances | ASG min = 0 | Fix ASG min count |
| **502** | App crashed mid-request | Logs: panic/crash | Fix application code |
| **502** | Protocol mismatch | LB sends HTTP, app expects HTTPS | Align protocols |
| **504** | LB timeout too short | Response time > LB timeout | Increase LB idle timeout |
| **504** | Slow DB query | DB slow query log | Optimise query, add index |
| **504** | App overloaded | CPU/memory at 100% | Scale out (more pods/instances) |
| **504** | Connection pool exhausted | DB connection errors in logs | Increase connection pool size |

---

## 5. Fixes

**Increase ALB idle timeout:**
```bash
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn arn:... \
  --attributes Key=idle_timeout.timeout_seconds,Value=120
```

**Scale out pods immediately (for 504 due to overload):**
```bash
kubectl scale deployment myapp --replicas=10 -n production
```

**Kubernetes — increase request timeout in Ingress:**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "120"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "120"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "30"
```

---

## 6. Prevention

| Measure | What it prevents |
|---------|-----------------|
| Set LB timeout > max app response time | 504 from timeout mismatch |
| Database connection pooling | Connection exhaustion under load |
| Circuit breaker pattern | Cascading failures → 503 across services |
| HPA (Horizontal Pod Autoscaler) | 504 from overload by auto-scaling |
| Slow query monitoring alerts | Catch DB issues before they cause 504s |

---

## Interview Answer

**Q: "Users are getting 503 errors — what do you check?"**

> "503 means the load balancer has no healthy backends. My first check is the target group health status — if all instances show unhealthy, the app has crashed or health checks are failing. I look at the health check failure reason: connection refused means the app isn't running, response code mismatch means the app is running but health endpoint is broken. If it's a 504, the app is running but responding slowly — I check database slow query logs first because slow DB queries are the most common cause of 504s in production. I also check if the LB idle timeout is shorter than the app's response time for that endpoint."
