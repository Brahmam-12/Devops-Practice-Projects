# Scenario 08: OOMKilled Pods

## Symptom
- Pod restarts repeatedly
- `kubectl describe pod` shows: `OOMKilled` in Last State
- Exit code 137 in pod events
- Alert: pod restarted N times

---

## 1. Understand the Architecture

```
OOMKilled = Out Of Memory Killed

When a container exceeds its memory LIMIT (not request):
  Kernel sends SIGKILL to the process → container exits immediately
  Exit code = 137 (128 + signal 9)
  Kubernetes restarts the container → it hits OOM again → CrashLoopBackOff

Memory Request vs Limit:
  Request = what the container is GUARANTEED (used for scheduling)
  Limit   = the MAXIMUM the container can use before being killed

  requests:
    memory: "256Mi"   ← scheduler reserves 256Mi on a node
  limits:
    memory: "512Mi"   ← container dies if it exceeds 512Mi
```

---

## 2. Identify OOMKill

```bash
kubectl describe pod <pod-name> -n production

# Look at: Last State section
# Last State: Terminated
#   Reason: OOMKilled       ← confirms OOM kill
#   Exit Code: 137
#   Finished: 2026-06-26 10:15:00

# Also check Events:
# Warning OOMKilling  node/mynode  Memory limit reached, killing process

# Check which container was OOMKilled (multi-container pods)
kubectl get pod <pod-name> -n production -o json \
  | jq '.status.containerStatuses[] | {name:.name, restartCount:.restartCount, lastState:.lastState}'
```

---

## 3. Troubleshooting Strategy

### Step 1: How much memory is the container actually using?

```bash
# Current memory usage
kubectl top pods <pod-name> -n production --containers

# Historical — if Prometheus available:
# container_memory_working_set_bytes{pod="myapp-xxx", container="myapp"}

# What is the current limit?
kubectl get pod <pod-name> -n production -o yaml | grep -A 5 resources:

# If usage is close to limit → increase limit
# If usage is growing over time → memory leak
```

---

### Step 2: Is this a memory leak or insufficient limit?

```bash
# Memory leak pattern:
# Pod starts at 200Mi → slowly grows → hits 512Mi limit → OOMKilled
# After restart: starts at 200Mi → grows again → OOMKilled again
# Watch memory over time:
watch -n 10 kubectl top pods -n production

# Insufficient limit pattern:
# Pod starts and immediately uses 600Mi (startup memory spike)
# Limit is 512Mi → OOMKilled on startup
# Fix: increase limit (app legitimately needs more)

# Check if app is a JVM — JVM heaps can cause this
kubectl exec <pod-name> -n production -- java -XX:+PrintFlagsFinal -version 2>&1 | grep MaxHeapSize
# If MaxHeapSize is 512MB but container limit is also 512MB → no room for anything else
```

---

### Step 3: Check application-level memory settings

```bash
# Node.js — default max heap is 1.5GB regardless of container limit
# If container limit is 512Mi and Node.js allocates 1.5GB → OOMKilled
# Fix: set NODE_OPTIONS="--max-old-space-size=400"

# JVM — set explicit heap size
# JAVA_OPTS="-Xmx400m -Xms256m" (leave room for JVM overhead ~200MB)
# If limit is 512Mi, set Xmx to 300-350m

# Python — usually no special setting needed, but watch for large dataframes/lists

# Check what env vars your app has for memory
kubectl exec <pod-name> -n production -- env | grep -i mem
kubectl exec <pod-name> -n production -- env | grep -i heap
kubectl exec <pod-name> -n production -- env | grep NODE_OPTIONS
```

---

## 4. Root Cause Analysis + Fix

| Root Cause | Evidence | Fix |
|-----------|----------|-----|
| Limit too low (app needs more) | Memory jumps to limit quickly on startup | Increase memory limit |
| Memory leak | Memory grows steadily over hours | Fix code leak, set limit + restart schedule |
| JVM heap > container limit | MaxHeapSize > container memory limit | Set -Xmx below container limit |
| Node.js default heap too large | NODE_OPTIONS not set | Add --max-old-space-size to NODE_OPTIONS |
| Caching too aggressively | In-memory cache unbounded | Add cache size limits |

---

## 5. Fix Commands

```bash
# Increase memory limit
kubectl patch deployment myapp -n production \
  --patch '{"spec":{"template":{"spec":{"containers":[{"name":"myapp","resources":{"requests":{"memory":"512Mi"},"limits":{"memory":"1Gi"}}}]}}}}'

# Set JVM heap (add to pod env)
kubectl patch deployment myapp -n production \
  --patch '{"spec":{"template":{"spec":{"containers":[{"name":"myapp","env":[{"name":"JAVA_OPTS","value":"-Xmx512m -Xms256m"}]}]}}}}'

# Set Node.js heap limit
kubectl patch deployment myapp -n production \
  --patch '{"spec":{"template":{"spec":{"containers":[{"name":"myapp","env":[{"name":"NODE_OPTIONS","value":"--max-old-space-size=400"}]}]}}}}'
```

---

## Interview Answer

**Q: "Pods keep getting OOMKilled — what do you do?"**

> "OOMKilled means the container exceeded its memory limit. Exit code 137 confirms this. First I check how much memory the container was using when it was killed using kubectl top, and compare that to the limit in the pod spec. If the app legitimately needs more memory, I increase the limit. If memory is growing steadily over time, that's a memory leak — I fix the code and set a higher limit as a temporary guard. For JVM apps, I make sure -Xmx is set well below the container memory limit because the JVM needs overhead beyond the heap. For Node.js, I add --max-old-space-size to NODE_OPTIONS to cap Node's memory usage explicitly."
