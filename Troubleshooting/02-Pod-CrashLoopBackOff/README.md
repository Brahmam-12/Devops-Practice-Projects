# Scenario 02: Pod CrashLoopBackOff

## Symptom
- `kubectl get pods` shows `CrashLoopBackOff` status
- Pod restarts repeatedly (RESTARTS column keeps going up)
- App is unavailable, requests failing
- Alert fires: pod restarting

---

## 1. Understand the Architecture

```
CrashLoopBackOff means:
  Pod starts → container runs → container exits (crashes) → Kubernetes restarts it
  → crashes again → Kubernetes waits (backoff: 10s, 20s, 40s, 80s, 5min)
  → restarts again → crashes again → cycle continues

Kubernetes restarts the container automatically, but keeps increasing the wait time
between restarts (exponential backoff) to avoid thrashing.
```

**Why does a container crash?**
- App code throws unhandled exception and exits
- App cannot connect to a required dependency (DB, another service)
- Missing environment variable the app requires
- OOM (Out of Memory) — process killed by kernel
- Liveness probe keeps failing → Kubernetes kills the container
- Bad Docker image / wrong entrypoint command

---

## 2. Identify the Symptom

```bash
kubectl get pods -n production

# Output:
NAME                    READY   STATUS             RESTARTS   AGE
myapp-6d9f8b-xk2p9     0/1     CrashLoopBackOff   8          12m

# READY 0/1 = container is not passing readiness probe
# RESTARTS 8 = crashed 8 times already
# CrashLoopBackOff = Kubernetes is in the restart backoff cycle
```

---

## 3. Troubleshooting Strategy

### Step 1: Get logs from the crashed container
**What:** What did the app print before it crashed?
**Why:** The crash reason is almost always in the application logs.

```bash
# Logs from current (possibly still crashing) container
kubectl logs <pod-name> -n production

# Logs from PREVIOUS run (before the last crash) — most useful!
kubectl logs <pod-name> -n production --previous

# If there are multiple containers in the pod
kubectl logs <pod-name> -c <container-name> -n production --previous

# Follow logs in real time to see crash as it happens
kubectl logs <pod-name> -n production -f
```

**What to look for:**
| Log pattern | Conclusion |
|------------|-----------|
| `Error: Cannot read env variable DATABASE_URL` | Missing environment variable |
| `connection refused` or `ECONNREFUSED` | Cannot reach DB or another service |
| `OOMKilled` or `Killed` | Process killed by kernel for using too much memory |
| `exec format error` | Docker image built for wrong architecture |
| `permission denied` | File permission issue in container |
| `SyntaxError` / `ModuleNotFoundError` | Bad code or missing package in image |
| No logs at all | Container exits immediately — check entrypoint/command |

---

### Step 2: Describe the pod — check events
**What:** What did Kubernetes observe about the pod's lifecycle?
**Why:** Events show exactly why the container was killed (OOM, probe failure, etc.)

```bash
kubectl describe pod <pod-name> -n production

# Look at the Events section at the bottom:
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Warning  BackOff    2m (x8 over 10m)  kubelet            Back-off restarting failed container
  Normal   Pulled     10m               kubelet            Successfully pulled image
  Warning  Failed     10m               kubelet            Error: failed to create containerd task:
  Normal   Created    10m               kubelet            Created container myapp

# Also check:
# Last State → Exit Code
# Exit Code 0   = app exited cleanly (check app logic — should NOT exit)
# Exit Code 1   = app crashed with error
# Exit Code 137 = OOMKilled (128 + signal 9)
# Exit Code 143 = SIGTERM (app got kill signal — maybe liveness probe timeout)
```

**Reading Exit Codes:**
```
Exit Code 0   → app exited cleanly — check if CMD/entrypoint is wrong
Exit Code 1   → app threw an error — check logs
Exit Code 137 → OOMKilled — container exceeded memory limit (→ Scenario 08)
Exit Code 143 → Liveness probe kept failing, Kubernetes killed it (→ check probe config)
```

---

### Step 3: Check environment variables and secrets
**What:** Does the pod have all the env vars it needs?
**Why:** Missing DATABASE_URL, API_KEY, etc. cause immediate crashes.

```bash
# Check what env vars the pod has
kubectl exec <pod-name> -n production -- env | sort

# Or check the pod spec
kubectl get pod <pod-name> -n production -o yaml | grep -A 20 env:

# Check if secrets are mounted correctly
kubectl get secrets -n production
kubectl describe secret myapp-secret -n production
# Look at Data section — shows key names (not values) that exist
```

**What to look for:**
```
If env var shows: DATABASE_URL=(not set) or is empty → secret not mounted or wrong key name
If secret missing → check if Secret exists in same namespace as pod
```

---

### Step 4: Check if the image is correct
**What:** Is the correct image being used? Does it exist?
**Why:** Wrong image tag, deleted image, or wrong registry causes `ImagePullBackOff` or exec errors.

```bash
kubectl describe pod <pod-name> -n production | grep Image:
# Image: myregistry.azurecr.io/myapp:v2.3

# Check if image exists in registry
# AWS ECR:
aws ecr describe-images --repository-name myapp --image-ids imageTag=v2.3

# Azure ACR:
az acr repository show-tags --name myregistry --repository myapp

# Pull and test locally
docker run --rm myregistry.azurecr.io/myapp:v2.3 echo "test"
```

---

### Step 5: Check resource limits
**What:** Does the container have enough CPU and memory to start?
**Why:** If memory limit is too low, container gets OOMKilled immediately.

```bash
kubectl get pod <pod-name> -n production -o yaml | grep -A 10 resources:

# Output example:
resources:
  requests:
    memory: "64Mi"
    cpu: "250m"
  limits:
    memory: "128Mi"   ← if app needs 200Mi to start → OOMKilled immediately
    cpu: "500m"
```

---

### Step 6: Check liveness probe
**What:** Is the liveness probe configuration correct?
**Why:** If liveness probe hits a path that doesn't exist or is too aggressive (short timeout), Kubernetes kills the container before it finishes starting.

```bash
kubectl get pod <pod-name> -n production -o yaml | grep -A 15 livenessProbe:

# livenessProbe:
#   httpGet:
#     path: /health
#     port: 8080
#   initialDelaySeconds: 5   ← too short? app might not be ready in 5s
#   periodSeconds: 10
#   failureThreshold: 3      ← fails 3 times in a row → container killed

# If app takes 30s to start but initialDelaySeconds is 5 → kills app while starting
```

---

## 4. Root Cause Analysis + Fix

| Root Cause | Confirm with | Fix |
|-----------|-------------|-----|
| Missing env var / secret | `kubectl exec -- env`, describe pod events | Add secret, fix env var name |
| App crashes on startup | `kubectl logs --previous` shows error | Fix application code |
| OOMKilled | Exit code 137, describe pod events | Increase memory limit |
| Wrong image / bad entrypoint | `docker run` locally fails | Fix Dockerfile CMD/ENTRYPOINT |
| Liveness probe too aggressive | `initialDelaySeconds` < startup time | Increase `initialDelaySeconds` or use `startupProbe` |
| Cannot reach database | Logs show connection refused | Fix DB service name, check NetworkPolicy |
| Image pull fails | `ImagePullBackOff` in describe | Fix registry credentials / image tag |

---

## 5. Fix Commands

```bash
# Fix 1: Rollback the deployment
kubectl rollout undo deployment/myapp -n production
kubectl rollout status deployment/myapp -n production

# Fix 2: Update env var (edit the deployment)
kubectl edit deployment myapp -n production
# change env vars inline, save → triggers rolling update

# Fix 3: Increase memory limit
kubectl patch deployment myapp -n production \
  --patch '{"spec":{"template":{"spec":{"containers":[{"name":"myapp","resources":{"limits":{"memory":"512Mi"}}}]}}}}'

# Fix 4: Increase liveness probe initial delay
kubectl patch deployment myapp -n production \
  --patch '{"spec":{"template":{"spec":{"containers":[{"name":"myapp","livenessProbe":{"initialDelaySeconds":60}}]}}}}'

# Fix 5: Force delete stuck pod (new one will be created by deployment)
kubectl delete pod <pod-name> -n production
```

---

## 6. Prevention

| Measure | What it prevents |
|---------|-----------------|
| `startupProbe` separate from `livenessProbe` | App killed while starting up |
| Resource requests + limits tuned properly | OOMKilled on startup |
| Validate all required env vars on startup | Missing config crashes |
| Test image locally before pushing | Bad image deployed |
| `readinessProbe` to control traffic | Traffic sent before app is ready |
| Set `terminationGracePeriodSeconds` | Ungraceful shutdown causing crashes |

---

## Interview Answer

**Q: "A pod is in CrashLoopBackOff — how do you debug it?"**

> "First I run kubectl logs with --previous to see what the app printed before it crashed. The exit code in kubectl describe tells me the type of crash — exit code 137 means OOMKilled, 143 means Kubernetes killed it because liveness probe failed. Then I check environment variables to see if a required config is missing. I also check resource limits — if the memory limit is too low the app gets killed immediately. Once I identify the root cause I either fix the code, add the missing secret, increase resource limits, or roll back the deployment. Going forward I'd use a startupProbe with a longer initialDelay to give the app time to start before liveness checks begin."
