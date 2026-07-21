# Scenario 03: Health Check Failures

## Symptom
- LB shows instances as "unhealthy" (AWS) or "degraded" (Azure)
- Pods not receiving traffic despite being Running
- 503 Service Unavailable from load balancer
- Alerts: target health check failing

---

## 1. Understand the Architecture

```
There are TWO types of health checks — both must pass for traffic to flow:

1. LOAD BALANCER health check (external)
   ALB / Azure LB → hits your app on a specific port + path → expects 200 OK
   If fails → removes instance from pool → no traffic sent to it

2. KUBERNETES probes (internal)
   kubelet → hits your container
   ├── readinessProbe → if fails → pod removed from Service endpoints (no traffic)
   ├── livenessProbe  → if fails → container killed and restarted
   └── startupProbe   → if fails → container killed before liveness begins

Both can independently remove a pod/instance from traffic rotation.
```

---

## 2. Identify the Symptom

| Symptom | Where to look |
|---------|--------------|
| AWS Target: "unhealthy" | EC2 → Target Groups → Health status |
| Azure backend: "unhealthy" | LB → Backend pools / App Gateway Backend health |
| Kubernetes pod: `0/1 READY` | `kubectl get pods` — READY column |
| Pod Running but no traffic | Readiness probe failing |
| Pod restarting repeatedly | Liveness probe failing |

---

## 3. Troubleshooting Strategy

### Step 1: Identify which health check is failing

**AWS:**
```bash
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# Output shows:
# HealthCheckPort: 80
# HealthCheckPath: /health
# State: unhealthy
# Reason: Target.ResponseCodeMismatch  → app returns non-2xx on /health
# Reason: Target.Timeout              → app takes too long to respond
# Reason: Target.FailedHealthChecks   → connection refused (app not listening on that port)
```

**Azure:**
```
Portal → Application Gateway → Backend Health
       → shows each backend server with Healthy / Unhealthy + HTTP status code returned
```

**Kubernetes:**
```bash
kubectl get pods -n production
# READY column: 0/1 = readiness probe failing, pod exists but gets no traffic

kubectl describe pod <pod-name> -n production
# Events section:
# Warning  Unhealthy  kubelet  Readiness probe failed: Get http://10.0.1.5:8080/ready: connection refused
# Warning  Unhealthy  kubelet  Liveness probe failed: HTTP probe failed with statuscode: 500
```

---

### Step 2: Test the health check endpoint manually
**What:** Does the app actually respond on the health check path and port?
**Why:** Confirms if the issue is the endpoint itself or the health check configuration.

```bash
# From inside the pod
kubectl exec <pod-name> -n production -- curl -v http://localhost:8080/health

# Expected: HTTP 200 OK
# If 404: health check path wrong (app uses /healthz or /api/health)
# If 500: app is broken internally
# If connection refused: app not listening on that port

# From EC2 instance — test the health check directly
curl -v http://localhost:80/health
curl -v http://10.0.3.x:80/health    # internal IP

# Test exactly what the LB tests:
curl -v -H "Host: myapp.com" http://10.0.3.x:80/health
```

---

### Step 3: Check health check configuration
**What:** Is the health check looking at the right port, path, and expecting the right status code?
**Why:** If app was updated and health endpoint moved, LB still checks old path.

**AWS:**
```bash
aws elbv2 describe-target-groups \
  --target-group-arns arn:... \
  --query "TargetGroups[0].{Port:HealthCheckPort,Path:HealthCheckPath,Protocol:HealthCheckProtocol,Matcher:Matcher}"

# Check:
# Port — does app listen on this port?
# Path — does this path return 200?
# Matcher — does LB expect 200 but app returns 201 or 204? → ResponseCodeMismatch
```

**Kubernetes:**
```bash
kubectl get deployment myapp -n production -o yaml | grep -A 30 "readinessProbe\|livenessProbe"

# readinessProbe:
#   httpGet:
#     path: /ready
#     port: 8080
#   initialDelaySeconds: 10
#   periodSeconds: 5
#   failureThreshold: 3
#   timeoutSeconds: 1     ← if app takes 2s to respond, this fails every time
```

---

### Step 4: Check if the app is actually listening on the expected port
**What:** What ports is the process listening on?
**Why:** App might start on 8080 but health check configured for 80, or app failed to bind.

```bash
# On EC2 / VM
netstat -tlnp | grep LISTEN
ss -tlnp

# Expected: 0.0.0.0:80 or 0.0.0.0:8080 with your app process
# If port not listed → app not listening → crashed or wrong port in config

# In Kubernetes pod
kubectl exec <pod-name> -n production -- netstat -tlnp
# or
kubectl exec <pod-name> -n production -- ss -tlnp
```

---

### Step 5: Check health endpoint logic
**What:** Is the health endpoint returning the right status code?
**Why:** App might return 200 but health check expects specific code, or health check does internal checks that fail.

```bash
# Detailed response inspection
kubectl exec <pod-name> -n production -- \
  curl -v -w "\nHTTP Status: %{http_code}\n" http://localhost:8080/health

# If app returns 200 but body says { "status": "degraded" }:
# → LB only checks status code, not body (LB health check would pass)
# → But if you have custom logic in health endpoint that fails DB check, etc.
```

**Common health endpoint patterns:**
```
/health      → basic: returns 200 if process is alive
/ready       → readiness: returns 200 only if app can serve traffic (DB connected, cache warmed)
/healthz     → Kubernetes convention
/api/health  → API-prefixed version

Problem: LB checks /health but app only has /healthz → 404 → unhealthy
```

---

## 4. Root Cause Analysis + Fix

| Root Cause | Evidence | Fix |
|-----------|----------|-----|
| Wrong health check path | curl returns 404 on checked path | Update health check path in LB/probe config |
| Port mismatch | `netstat` shows different port | Fix LB target port or app port |
| App returning 500 | curl returns 500 with error body | Fix application health endpoint code |
| Timeout too short | App takes 3s, timeout is 1s | Increase `timeoutSeconds` in probe |
| `initialDelaySeconds` too short | Pod kills before app starts | Increase to 30–60s or use `startupProbe` |
| App depends on DB which is down | Health endpoint checks DB | Fix DB connection, or make health check not block on DB |
| Security Group blocks LB | Connection refused from LB | Add inbound rule for LB IP range on app port |

---

## 5. Fix Commands

**AWS — Update health check path:**
```bash
aws elbv2 modify-target-group \
  --target-group-arn arn:... \
  --health-check-path /healthz \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2
```

**Kubernetes — Update readiness probe:**
```bash
kubectl patch deployment myapp -n production --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/healthz"}]'

# Or edit directly:
kubectl edit deployment myapp -n production
```

**Kubernetes — Best practice probe setup:**
```yaml
# Use all three probes together:
startupProbe:           # gives app time to start
  httpGet:
    path: /health
    port: 8080
  failureThreshold: 30  # 30 × 10s = 5 minutes to start
  periodSeconds: 10

livenessProbe:          # kills if stuck/hung
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 0
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:         # controls traffic routing
  httpGet:
    path: /ready        # can be different from /health
    port: 8080
  periodSeconds: 5
  failureThreshold: 2
```

---

## 6. Prevention

| Measure | What it prevents |
|---------|-----------------|
| Separate `/health` and `/ready` endpoints | Traffic routed to pod before it's ready |
| `startupProbe` for slow-starting apps | Container killed during startup |
| Health check path documented in README | Misconfiguration on deploy |
| Monitor health check success rate | Catch intermittent failures before they become outages |
| Health endpoint that checks dependencies | App reports healthy but cannot serve requests |

---

## Interview Answer

**Q: "Load balancer shows instances unhealthy — how do you debug?"**

> "I start by checking what the load balancer reports as the reason — whether it's a response code mismatch, timeout, or connection refused. Each tells me something different. Connection refused means the app isn't listening on the expected port. Timeout means it's responding too slowly. Response code mismatch means the app is running but returning a non-200 status. I then test the health check endpoint directly from inside the instance using curl to confirm what the app actually returns. I also check if the health check port and path in the LB config match what the new version of the app exposes. A common issue I've seen is the health check path changing between versions — say from /health to /healthz — but the LB config wasn't updated."
