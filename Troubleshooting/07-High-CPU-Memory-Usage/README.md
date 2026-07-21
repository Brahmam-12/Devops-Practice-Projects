# Scenario 07: High CPU or Memory Usage

## Symptom
- CloudWatch / Azure Monitor alert: CPU > 80% for 15 minutes
- Application is slow, request latency increased
- Pods getting throttled or OOMKilled
- Autoscaler triggered but instances still saturated

---

## 1. Understand the Architecture

```
CPU high → requests queue up → response time increases → users see slow app → 504s
Memory high → swap (if enabled) → I/O thrash → OOMKill → crash → CrashLoopBackOff

CPU and memory issues can be:
  Application level  → bad code (infinite loop, memory leak, N+1 queries)
  Infra level        → too few replicas, undersized instances
  Traffic level      → traffic spike (legit or DDoS/bot)
  System level       → background process consuming resources (cron, log rotation)
```

---

## 2. Troubleshooting Strategy

### Step 1: Identify WHAT is consuming CPU/memory

**AWS EC2:**
```bash
# Top processes by CPU
top -b -n 1 | head -20
# or
ps aux --sort=-%cpu | head -10     # sort by CPU
ps aux --sort=-%mem | head -10     # sort by memory

# If it's your app → code issue
# If it's a system process (kswapd, mysqld, java GC) → different issue
```

**Kubernetes:**
```bash
# Which nodes are overloaded?
kubectl top nodes

# Which pods on those nodes?
kubectl top pods -n production
kubectl top pods -n production --sort-by=cpu
kubectl top pods -n production --sort-by=memory

# Which containers inside a pod?
kubectl top pods <pod-name> -n production --containers
```

**Azure VM:**
```bash
# Same as Linux EC2
top -b -n 1 | head -20
ps aux --sort=-%cpu | head -10

# Azure Monitor also shows per-process CPU in Insights:
# Portal → VM → Insights → Performance
```

---

### Step 2: Check if it's a traffic spike or a code problem

```bash
# Traffic spike = sudden CPU jump matching traffic increase
# Memory leak = CPU/memory grows slowly over time without traffic increase

# Check request count over time (AWS)
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name RequestCount \
  --dimensions Name=LoadBalancer,Value=app/my-alb/xxx \
  --start-time 2026-06-26T08:00:00 \
  --end-time 2026-06-26T10:00:00 \
  --period 300 --statistics Sum

# If requests doubled and CPU doubled → traffic spike (need to scale)
# If requests flat but CPU/memory climbing → code problem (leak, runaway loop)
```

---

### Step 3: Check for memory leaks

```bash
# On EC2 — watch memory over time
watch -n 5 free -m
# total: stays same
# used: keeps growing without traffic → memory leak

# Check if a process is leaking
watch -n 5 "ps aux --sort=-%mem | head -5"

# Kubernetes — check if memory grows after restarts
kubectl top pods -n production
# If pod restarts and memory immediately goes to 80% → leak in app code
# If memory grows over hours → slower leak
```

---

### Step 4: Check if it's CPU throttling in Kubernetes

```bash
# CPU throttling happens when container hits its CPU limit
# Different from CPU "high usage" — throttling means requests are being delayed

kubectl describe pod <pod-name> -n production
# Look at: CPU throttled

# Or check metrics (if Prometheus installed)
# container_cpu_cfs_throttled_seconds_total → shows throttling time

# If throttled → increase CPU limit or request more resources
kubectl get pod <pod-name> -n production -o yaml | grep -A 5 resources:
# limits.cpu: "500m" → only 0.5 CPU cores, might be too low
```

---

### Step 5: Check for runaway processes

```bash
# Is a specific process consistently at 100% CPU?
top
# Press 'P' to sort by CPU
# If one PID is at 100% and it's your app → check app logs for infinite loops

# Find what's running inside a Kubernetes pod
kubectl exec <pod-name> -n production -- top
kubectl exec <pod-name> -n production -- ps aux

# Check if it's a cron job or background task
crontab -l
cat /etc/cron.d/*
```

---

### Step 6: Check database — N+1 queries cause high CPU

```bash
# App making too many DB queries → DB CPU spikes → app waits → cascading slowness

# AWS RDS — check active queries
aws rds describe-db-instances --db-instance-identifier mydb
# Then check Enhanced Monitoring or Performance Insights in Console

# Kubernetes — exec into app pod and check DB connections
kubectl exec <pod-name> -n production -- \
  psql -h db-host -U user -c "SELECT pid, query, state FROM pg_stat_activity ORDER BY query_start;"
# COUNT of connections > connection_pool_size → pool exhausted
# Long-running queries → blocking other queries
```

---

## 4. Root Cause Analysis + Fix

| Root Cause | Evidence | Fix |
|-----------|----------|-----|
| Traffic spike | Request count and CPU rose together | Scale out (more pods/instances) |
| Memory leak | Memory grows continuously, doesn't drop | Fix code, restart as temp fix, set memory limits |
| CPU throttling | Kubernetes throttled CPU metric high | Increase CPU limit in pod spec |
| Infinite loop / runaway thread | Single process at 100% CPU | Check recent code changes, kill and restart |
| N+1 DB queries | DB CPU high, many small queries in logs | Batch queries, add DB index, ORM eager loading |
| GC pressure (JVM/Node) | App pauses, memory fluctuates | Tune GC settings, increase heap size |
| Bot/DDoS | Many requests from few IPs, all identical | Block at WAF/ALB level (rate limiting, IP block) |

---

## 5. Immediate Fixes

```bash
# Scale out immediately to reduce load per instance
kubectl scale deployment myapp --replicas=10 -n production

# AWS — trigger ASG scale out
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name my-asg \
  --desired-capacity 10

# If a specific pod is stuck — restart it
kubectl delete pod <stuck-pod-name> -n production

# If memory leak — restart all pods with zero downtime (rolling restart)
kubectl rollout restart deployment/myapp -n production

# Kubernetes — increase resources temporarily
kubectl patch deployment myapp -n production \
  --patch '{"spec":{"template":{"spec":{"containers":[{"name":"myapp","resources":{"limits":{"cpu":"2","memory":"1Gi"}}}]}}}}'
```

---

## Interview Answer

**Q: "CPU is at 95% on your production instances — what do you do?"**

> "First I need to know if this is a traffic spike or a code problem — I check if the request count increased proportionally with CPU. If traffic spiked, I scale out immediately to distribute load. If traffic is normal but CPU is high, I look at which process is consuming it — top or kubectl top pods. A runaway process or infinite loop shows as one process at 100% CPU. For memory, I watch if it grows over time without dropping — that's a leak. The immediate fix is to scale out and restart affected instances. Then I investigate root cause: check recent deploys, check DB query patterns, and check for any code that might loop indefinitely."
