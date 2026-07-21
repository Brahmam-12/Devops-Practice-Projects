# Scenario 10: CI/CD Pipeline Failures

## Symptom
- GitHub Actions / Azure DevOps / Jenkins build is failing
- Deployment did not reach production
- Red X on the pipeline, team is blocked from deploying
- Alert: pipeline has been failing for > 1 hour

---

## 1. Understand the Architecture

```
CI/CD Pipeline stages (each can fail independently):

1. Trigger       → push to branch / PR / tag / manual
2. Checkout      → clone the repository
3. Build         → compile code, build Docker image
4. Test          → unit tests, integration tests, lint
5. Push          → push Docker image to registry (ECR / ACR)
6. Deploy        → kubectl apply / terraform apply / ansible
7. Verify        → smoke test, health check after deploy

Common failure points:
  Build fails    → code error, missing dependency, Dockerfile issue
  Test fails     → broken test, environment issue, flaky test
  Push fails     → registry auth, rate limit, disk space
  Deploy fails   → auth to cluster, wrong kubeconfig, resource quota
  Verify fails   → app starts but doesn't pass smoke test
```

---

## 2. Troubleshooting Strategy

### Step 1: Read the failure message — where exactly did it fail?

```
The pipeline log always tells you the exact step and error.
Never skip reading the full error message.

Common patterns:
  "Error: Cannot find module 'xxx'"      → npm install failed or missing package
  "authentication required"              → registry login failed
  "permission denied"                    → wrong IAM role / service principal
  "timeout"                              → network issue or slow step
  "exit code 1"                          → command failed, read the line before
  "ERRO[xxxx] context deadline exceeded" → kubectl timed out reaching cluster
```

---

### Step 2: GitHub Actions — check logs

```yaml
# In the Actions log, click the failed step to expand it
# The last few lines before the red X show the error

# Common: secrets not set
# Error: Input required and not supplied: aws-access-key-id
# Fix: Settings → Secrets → add the missing secret

# Common: wrong branch protection rule
# Error: Process completed with exit code 128
# fatal: unable to access 'https://github.com/...': The requested URL returned error: 403

# Reproduce locally
act -j build      # 'act' tool runs GitHub Actions locally for debugging
```

---

### Step 3: Check authentication / credentials

```bash
# AWS ECR push failing?
# Error: no basic auth credentials

# Fix: make sure the pipeline logs in first
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com

# GitHub Actions — check if IAM role has ECR permissions
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123:role/github-actions-role \
  --action-names ecr:GetAuthorizationToken ecr:BatchCheckLayerAvailability \
  --resource-arns "*"

# Azure ACR push failing?
# Error: unauthorized: authentication required
az acr login --name myregistry
# Or use service principal:
docker login myregistry.azurecr.io -u <appId> -p <password>
```

---

### Step 4: Check Docker build failures

```bash
# Build failures in pipeline — reproduce locally first
docker build -t myapp:test .

# Common:
# COPY failed: file not found → .dockerignore is excluding files you need
# RUN npm install: ENOPACKAGE → package not in registry, private package needs auth
# Layer cache invalidated → slow build (not a failure but annoying)

# Check .dockerignore isn't too aggressive
cat .dockerignore | grep -v "^#"
```

---

### Step 5: kubectl deploy step fails

```bash
# Error: unable to connect to server
# → Pipeline cannot reach the Kubernetes cluster

# Check kubeconfig in pipeline
# GitHub Actions:
# - uses: azure/k8s-set-context@v3 (Azure)
# - uses: aws-actions/amazon-eks-update-kubeconfig (AWS)

# AWS EKS — check pipeline role has EKS access
aws eks update-kubeconfig --region us-east-1 --name my-cluster
kubectl get nodes

# Error: Forbidden — pipeline service account lacks RBAC
kubectl get rolebinding -n production | grep pipeline
kubectl describe rolebinding pipeline-deployer -n production
```

---

### Step 6: Flaky tests — non-deterministic failures

```bash
# Test passes locally, fails in pipeline randomly
# Common causes:
#   Test depends on external service (make it mock)
#   Test has time-dependent logic (use fake clock)
#   Test depends on ordering (each test should be independent)
#   Resource not cleaned up between tests (race condition)

# Check test failure frequency
# GitHub Actions: Actions → select workflow → see pass/fail history over time
# If failure rate is ~20% with same code → flaky test

# Rerun the failed job to confirm flakiness
# GitHub Actions: Failed job → Re-run failed jobs
```

---

## 4. Root Cause Analysis + Fix

| Stage | Root Cause | Evidence | Fix |
|-------|-----------|----------|-----|
| Build | Missing dependency | npm ERR or pip error | Add package, fix Dockerfile |
| Build | .dockerignore too aggressive | COPY fails | Remove overly broad ignore rules |
| Test | Flaky test | Passes on rerun | Fix test isolation, use mocks |
| Push | Registry auth expired | unauthorized error | Refresh credentials / rotate secret |
| Push | ECR repo missing | repository not found | Create ECR repository |
| Deploy | RBAC missing | Forbidden | Add ClusterRole/RoleBinding for pipeline SA |
| Deploy | Quota exceeded | exceeded quota | Increase namespace resource quota |
| Verify | Smoke test fails | App not responding | → Scenario 01 (website down after deploy) |

---

## 5. Prevention

| Measure | What it prevents |
|---------|-----------------|
| Reproducible local build (Docker) | "works on my machine" failures |
| Rotate credentials before expiry | Auth failures in pipeline |
| RBAC least-privilege for pipeline SA | Over-permission or permission gaps |
| Retry on transient failures | One-off network timeouts blocking deploy |
| Cache dependencies | Slow builds from downloading packages |
| Pipeline as code (YAML in repo) | Pipeline config drift |

---

## Interview Answer

**Q: "CI/CD pipeline is failing — how do you debug it?"**

> "I read the pipeline log from the top of the failed step — the error message tells me exactly which step failed. Is it the build, the test, the push to registry, or the deploy to cluster? For auth errors I check if credentials are expired — ECR tokens expire every 12 hours and need to be refreshed. For kubectl failing to reach the cluster I check if the kubeconfig context is set correctly in the pipeline. For flaky tests I look at the failure history — if it fails 20% of the time with no code changes, it's a test isolation issue. For deploy failing with Forbidden, it's an RBAC issue — I check if the pipeline service account has the necessary ClusterRole bound to it."
