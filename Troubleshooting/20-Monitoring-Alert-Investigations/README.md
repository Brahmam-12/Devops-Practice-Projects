# Scenario 20: Monitoring and Alert Investigations

## Symptom
- PagerDuty / OpsGenie alert fires at 2am
- Prometheus alert: "HighErrorRate" or "PodCrashingTooOften"
- Azure Monitor alert: "CPU > 80% for 15 minutes"
- Alert fired but nothing seems wrong — false positive?

---

## 1. Understand the Architecture

```
Observability has three pillars:

METRICS    → numbers over time (CPU %, request rate, error count, latency p99)
             Tools: Prometheus + Grafana, CloudWatch, Azure Monitor
             
LOGS       → what happened and when (app logs, system logs, audit logs)
             Tools: ELK, Loki + Grafana, CloudWatch Logs, Azure Log Analytics
             
TRACES     → full path of a request through microservices
             Tools: Jaeger, Zipkin, AWS X-Ray, Azure Application Insights

Alert fires → check METRICS first (what is wrong?)
            → check LOGS (why is it wrong?)
            → check TRACES (which service in the chain caused it?)
```

---

## 2. Troubleshooting Strategy

### Step 1: Understand what the alert is measuring

```
NEVER immediately start restarting things when an alert fires.
First: understand what the alert measures and what triggered it.

Alert: "ErrorRate > 5% for 5 minutes"
  → What counts as an error? HTTP 5xx? 4xx? App-logged errors?
  → 5 minutes means it's sustained, not a brief spike
  → Start: check current error rate in Grafana

Alert: "HighMemory > 80% for 15 minutes"
  → Which pod/node? All or specific?
  → Is it growing (leak) or steady (needs more resources)?
  → Start: kubectl top pods / CloudWatch
```

---

### Step 2: Check metrics dashboard

```bash
# Kubernetes — what does the Grafana dashboard show?
# Navigate to: Grafana → Kubernetes → select namespace → select pod
# Key panels to check:
#   Request rate (RPS) — is traffic normal or spiked?
#   Error rate (%) — what % of requests are failing?
#   P99 latency — how slow is the slowest 1% of requests?
#   Memory usage — growing or stable?
#   CPU usage — spiked or steady?

# Check Prometheus directly
kubectl port-forward svc/prometheus -n monitoring 9090:9090
# In browser: http://localhost:9090
# Query: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])
# → current error rate
```

---

### Step 3: Correlate with logs

```bash
# Find the time the alert fired → look at logs from that time

# Kubernetes — filter logs by time
kubectl logs deployment/myapp -n production \
  --since=30m | grep -i "error\|exception\|failed"

# CloudWatch Logs Insights (AWS)
aws logs start-query \
  --log-group-name /aws/eks/myapp \
  --start-time $(date -d "30 minutes ago" +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 50'

# Azure Log Analytics (Kusto)
# ContainerLog
# | where TimeGenerated > ago(30m)
# | where LogEntry contains "ERROR"
# | order by TimeGenerated desc
# | take 50
```

---

### Step 4: Is the alert a false positive?

```bash
# False positive indicators:
# Alert fired but metrics are now back to normal (brief spike during deploy)
# Alert threshold too aggressive (CPU > 50% is not always a problem)
# Alert fires every Monday morning (expected traffic pattern)

# Check alert history
# Prometheus AlertManager: port-forward and browse active/resolved alerts
kubectl port-forward svc/alertmanager -n monitoring 9093:9093

# If alert resolved itself → investigate what caused the brief spike
# Was there a deployment at that time?
kubectl rollout history deployment/myapp -n production

# Was there a traffic spike?
# Check LB request count graph during alert window
```

---

### Step 5: Verify the fix worked

```bash
# After applying a fix, confirm metrics return to normal
# Check error rate is below threshold
# Check latency is back to baseline
# Watch for 15 minutes to confirm alert doesn't re-fire

# Post-incident: write what you found
# What time did the alert fire?
# What was the root cause?
# What did you do to fix it?
# How do we prevent it?
```

---

## 4. Alerting Best Practices

| Problem | Better approach |
|---------|----------------|
| Alert on CPU > 80% | Alert on CPU > 80% FOR 15 minutes (avoid false positives on spikes) |
| Alert on every 5xx | Alert on ERROR RATE > 1% (tolerate occasional errors) |
| Too many alerts | Group related alerts, set severity levels |
| Alert with no runbook | Add runbook link to every alert (what to check) |
| Alert on symptoms not causes | Alert on latency/error rate (user impact), not just CPU |

---

## Interview Answer

**Q: "You get paged at 2am — CPU alert fired. What do you do?"**

> "First I don't panic and start restarting things. I look at the monitoring dashboard to understand the scope — is it one pod, all pods, or a node? I check if the CPU spike correlates with a traffic increase or a deployment. If traffic is normal and CPU is still climbing, I check which process is consuming CPU inside the pod. If it's a sustained spike with no traffic change, I look at recent code changes. The first action might be to scale out to reduce load per instance while I investigate. I document everything — time of alert, what I found, what I changed — because at 2am memory is unreliable and a written log is essential for the post-mortem."
