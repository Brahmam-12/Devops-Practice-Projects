# Scenario 16: Secret and ConfigMap Issues

## Symptom
- Pod fails to start: `CreateContainerConfigError`
- App crashes with "environment variable not set"
- App has wrong configuration (using old config after update)
- Pod shows: `Error: secret "myapp-secret" not found`

---

## 1. Understand the Architecture

```
ConfigMap → non-sensitive config (DB host, log level, feature flags)
Secret    → sensitive config (passwords, API keys, TLS certs)

Mounted in pods as:
  Environment variables: value pulled at pod START
  Volume mount:          file updated when ConfigMap/Secret changes (with delay)

Key rules:
  Secrets must be in SAME namespace as the pod
  Secret key names are case-sensitive
  Base64 encoding in Secret is NOT encryption (just encoding)
  Pod env vars are NOT updated after pod starts — need restart for new values
```

---

## 2. Troubleshooting Strategy

### Step 1: Check CreateContainerConfigError

```bash
kubectl describe pod <pod-name> -n production

# Events:
# Warning  Failed  kubelet  Error: secret "myapp-secret" not found
# Warning  Failed  kubelet  Error: configmap "myapp-config" not found

# Secret doesn't exist in this namespace
kubectl get secrets -n production | grep myapp

# ConfigMap doesn't exist
kubectl get configmaps -n production | grep myapp
```

---

### Step 2: Check if keys exist in the Secret/ConfigMap

```bash
# List keys in a secret (values hidden)
kubectl describe secret myapp-secret -n production
# Data:
# ====
# DATABASE_URL: 45 bytes   ← key exists
# API_KEY:      32 bytes   ← key exists
# JWT_SECRET:   0 bytes    ← key exists but EMPTY (common mistake)

# List keys in configmap
kubectl describe configmap myapp-config -n production

# Check if pod env var references correct key name
kubectl get deployment myapp -n production -o yaml | grep -A 5 secretKeyRef:
# secretKeyRef:
#   name: myapp-secret
#   key: DATABASE_URL    ← does this key exist in the secret?
```

---

### Step 3: Decode and verify a secret value

```bash
# Get the base64 value
kubectl get secret myapp-secret -n production \
  -o jsonpath='{.data.DATABASE_URL}'

# Decode it
kubectl get secret myapp-secret -n production \
  -o jsonpath='{.data.DATABASE_URL}' | base64 -d

# If output is wrong value → update the secret
kubectl create secret generic myapp-secret \
  --from-literal=DATABASE_URL="postgresql://user:pass@host:5432/db" \
  --dry-run=client -o yaml | kubectl apply -f -
```

---

### Step 4: Config updated but pod still uses old value

```bash
# Env vars from ConfigMap/Secret are set at POD START
# Updating ConfigMap does NOT update running pods
# Must restart pods to pick up new values

kubectl rollout restart deployment/myapp -n production

# Volume-mounted ConfigMaps DO update eventually (kubelet syncs ~1-2 min)
# But env vars NEVER update without restart

# Verify new value is in running pod
kubectl exec <pod-name> -n production -- env | grep DATABASE_URL
```

---

### Step 5: Secret in wrong namespace

```bash
# Secret exists in 'default' namespace but pod is in 'production'
kubectl get secret myapp-secret -n default   # exists here
kubectl get secret myapp-secret -n production # not found here

# Copy secret to correct namespace
kubectl get secret myapp-secret -n default -o yaml \
  | sed 's/namespace: default/namespace: production/' \
  | kubectl apply -f -
```

---

## 4. Root Cause + Fix

| Root Cause | Evidence | Fix |
|-----------|----------|-----|
| Secret doesn't exist | `not found` error in pod events | Create the secret |
| Wrong namespace | Secret in default, pod in production | Copy secret to correct namespace |
| Wrong key name | Key exists but env var shows empty | Fix key name in pod spec or secret |
| Config updated, pod not restarted | Old value still in `env` output | `kubectl rollout restart` |
| Empty secret value | Key shows 0 bytes | Re-create secret with correct value |

---

## Interview Answer

**Q: "Pod has CreateContainerConfigError — how do you debug?"**

> "I run kubectl describe pod and read the Events — it tells me exactly which secret or configmap was not found. I then check if the resource exists in the SAME namespace as the pod using kubectl get secrets. If the secret exists, I check that the key name referenced in the pod spec exactly matches a key in the secret — case sensitive. A common issue I've seen is a config update that doesn't take effect because env vars from secrets are set at pod start time, not dynamically — you need a rolling restart to pick up new values."
