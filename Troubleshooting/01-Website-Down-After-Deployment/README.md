# Scenario 01: Website Down After Deployment
>"After confirming the pipeline succeeded, I'll verify whether the request is progressing through each layer of the architecture. 

> First, I'll confirm the Load Balancer is active and accepting requests.

> Next, I'll inspect the Target Group health. If the targets are unhealthy, I'll investigate whether the health check path, backend application port, or health check response has changed after the deployment.

> If the Target Group is healthy, I'll move into the Kubernetes cluster. I'll verify that the Ingress rules correctly route traffic to the expected Service. Then I'll confirm the Service has active Endpoints, ensuring it is selecting the intended Pods. If the Endpoints are missing, I'll investigate label selectors and deployment configuration.

> Once I know traffic can reach the Pods, I'll inspect the Pod status, readiness probes, and application logs. Finally, I'll verify environment variables, Secrets, ConfigMaps, and database connectivity if the application is still failing."

## Symptom
- Users report the website is down
- You or the team just deployed a new version
- HTTP 5xx errors or connection timeouts
- Monitoring alerts firing

---

## 1. Understand the Architecture

```
User Browser
    │
    ▼
DNS (Route 53 / Azure DNS)
    │
    ▼
Load Balancer (ALB / Azure LB)
    │  ← runs health checks on targets
    ▼
Target Group / Backend Pool
    │
    ▼
EC2 / VM / Pod (your application)
    │
    ▼
Database (RDS / Azure SQL)
```

**Which components could cause the site to go down after a deploy?**
- The app itself crashed (bad code, missing env var)
- The new container/image failed to start
- Config file changed wrongly (wrong DB connection string, wrong port)
- Health check fails → LB removes all instances from rotation
- Database migration ran and broke the schema
- Wrong port exposed or SG/NSG rule missing

---

## 2. Identify the Symptom

| What user sees | Likely layer |
|---------------|-------------|
| Cannot connect at all (connection refused) | App not running, port wrong, SG block |
| 502 Bad Gateway | LB cannot reach backend (app crashed, wrong port) |
| 503 Service Unavailable | No healthy targets in LB pool |
| 504 Gateway Timeout | App running but taking too long to respond |
| 200 OK but blank page / JS errors | Frontend deployed but backend API down |

---

## 3. Troubleshooting Strategy

### Step 1: Check if the LB has healthy targets
**What:** Is the load balancer sending traffic to any instance?
**Why:** LB removes unhealthy instances — if all instances fail health checks, all traffic 503s.

**AWS:**
```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:123:targetgroup/my-tg/abc

# What to look for in output:
# "State": "healthy"    → LB is sending traffic to this instance
# "State": "unhealthy"  → health check is failing on this instance
# "State": "draining"   → instance being removed (deployment in progress)
# "Reason": "Target.ResponseCodeMismatch" → app returning non-2xx, check app logs
# "Reason": "Target.Timeout"              → app not responding in time
# "Reason": "Target.FailedHealthChecks"   → connection refused, app may have crashed
```

**Azure:**
```
Portal: Load Balancer → Backend Pools → check instance health status
     OR: Application Gateway → Backend Health tab
        → shows each backend VM with Healthy / Unhealthy status + reason
```

**Conclusion:**
- All healthy → LB is working, problem is elsewhere (DNS, app logic)
- All unhealthy → app crashed or wrong port → go to Step 2
- Some healthy, some unhealthy → partial deploy issue or rolling deploy in progress

---

### Step 2: Check the application logs on the instance
**What:** What is the app saying when it starts?
**Why:** App startup errors, missing config, wrong DB URL all show here.

**AWS (EC2):**
```bash
# SSH into the unhealthy EC2 instance
ssh -i key.pem ec2-user@10.0.3.x

# Check if the app process is running
ps aux | grep node          # or java, python, gunicorn, nginx — whatever your app is
systemctl status myapp      # if managed by systemd

# Check app logs (adjust path to your app)
journalctl -u myapp -n 100 --no-pager   # systemd logs, last 100 lines
tail -100 /var/log/myapp/app.log
```

**Kubernetes:**
```bash
# Get all pods and their status
kubectl get pods -n production

# Get logs from the crashing pod
kubectl logs <pod-name> -n production

# Get logs from the previous crashed instance (before restart)
kubectl logs <pod-name> -n production --previous

# Describe to see events (why did pod fail to start?)
kubectl describe pod <pod-name> -n production
```

**Azure (VM):**
```bash
# SSH into VM
# Check app process
systemctl status myapp
journalctl -u myapp -n 100

# Or check Azure App Service logs:
# Portal → App Service → Log stream → see live logs
```

**What to look for in logs:**
| Log message | Conclusion |
|------------|-----------|
| `Cannot connect to database` | DB connection string wrong or DB is down |
| `Port already in use` | Previous process didn't stop, port conflict |
| `Module not found` | Bad deployment, missing dependency |
| `Permission denied` | File permissions wrong after deploy |
| `Environment variable not set` | Missing env var, config not deployed |
| `SyntaxError` | Bad code deploy, file corrupted |

---

### Step 3: Check recent deployment
**What:** What exactly changed in this deployment?
**Why:** Something changed → something broke. Narrowing the diff narrows the root cause.

```bash
# Git — what changed in this deploy?
git log --oneline -10                    # last 10 commits
git diff HEAD~1 HEAD -- config/          # config changes in last commit
git diff HEAD~1 HEAD -- package.json     # dependency changes

# Docker — which image was deployed?
docker ps                                # what image is running now
docker images | head -5                  # recent images

# Kubernetes — what changed?
kubectl rollout history deployment/myapp -n production
kubectl describe deployment myapp -n production | grep Image

# AWS — what ASG/LB changed?
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names my-asg
```

---

### Step 4: Check the health check configuration
**What:** Is the health check path and port correct for the new version?
**Why:** If the new version changed the health check endpoint (e.g. `/health` → `/api/health`) but LB still checks old path, all instances fail.

**AWS:**
```bash
aws elbv2 describe-target-groups \
  --target-group-arns arn:... \
  --query "TargetGroups[0].{Port:Port,Protocol:Protocol,Path:HealthCheckPath}"

# What to look for:
# Port: 80   → does your app run on 80? Or did the new version use 8080?
# Path: /    → does this path return 200? Or did the new version move health check?
```

**Azure:**
```
Portal → Load Balancer → Health Probes → check port and path
       → Application Gateway → Health Probes → same
```

---

### Step 5: Check Security Groups / NSGs (if connection refused)
**What:** Is the firewall blocking the new port?
**Why:** If the new version runs on port 8080 but SG only allows port 80, all connections are refused.

**AWS:**
```bash
aws ec2 describe-security-groups --group-ids sg-xxxxx \
  --query "SecurityGroups[0].IpPermissions"
# Look for: FromPort, ToPort — does it match the port your app uses?
```

**Azure:**
```
Portal → Network Security Group → Inbound rules
       → check if port matches what app listens on
```

---

### Step 6: Test the app directly (bypass LB)
**What:** Does the app respond if you call it directly, skipping the LB?
**Why:** Confirms if the issue is the app vs the LB configuration.

```bash
# From the instance itself — does it respond?
curl -v http://localhost:80/        # or whatever port
curl -v http://localhost:80/health

# From bastion — does it respond on internal IP?
curl -v http://10.0.3.x:80/

# If app responds directly but not through LB → LB config issue (health check path, port)
# If app doesn't respond directly → app itself is the problem (crashed, wrong port)
```

---

## 4. Root Cause Analysis

| Root Cause | How to confirm | Fix | Prevention |
|-----------|----------------|-----|------------|
| App crashed at startup | `journalctl` / `kubectl logs --previous` shows crash | Fix code, redeploy | Unit tests, smoke tests pre-deploy |
| Wrong DB connection string | Logs show `Cannot connect to database` | Fix env var / secret | Environment-specific config validation |
| Port mismatch (app:8080, LB:80) | `netstat -tlnp` shows port, LB shows different | Fix LB or app port | Document port in config, test in staging |
| Health check path changed | LB check hits old path, app returns 404 | Update health check path | Keep health check path stable across versions |
| Bad Docker image | `docker logs` shows immediate exit | Pull previous image or rebuild | Image smoke test before push to registry |
| DB migration failed | App logs `table does not exist` | Roll back migration or run manually | Test migrations in staging, use rollback scripts |

---

## 5. Fix — Rollback (fastest recovery)

**AWS — Roll back ASG to previous Launch Template version:**
```bash
# Find previous launch template version
aws ec2 describe-launch-template-versions --launch-template-id lt-xxxx

# Update ASG to use previous version
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name my-asg \
  --launch-template LaunchTemplateId=lt-xxxx,Version=1

# Trigger instance refresh to replace instances
aws autoscaling start-instance-refresh --auto-scaling-group-name my-asg
```

**Kubernetes — Roll back deployment:**
```bash
# Immediate rollback to previous version
kubectl rollout undo deployment/myapp -n production

# Rollback to specific version
kubectl rollout undo deployment/myapp --to-revision=3 -n production

# Watch the rollback happen
kubectl rollout status deployment/myapp -n production
```

**Azure — App Service rollback:**
```
Portal → App Service → Deployment Center → Deployment history → select previous deploy → Redeploy
```

---

## 6. Prevention

| Measure | What it prevents |
|---------|-----------------|
| **Smoke tests in pipeline** | Catches broken deployments before they reach production |
| **Blue-Green deployment** | New version tested on Green, switch DNS only when healthy |
| **Canary deployment** | 5% traffic to new version, monitor, then roll out fully |
| **Health check endpoint** | Standardise `/health` across all services, never change the path |
| **Deployment runbook** | Checklist of what to verify before and after each deploy |
| **Automated rollback trigger** | If error rate > X% after deploy → auto rollback |

---

## Interview Answer

**Q: "Tell me about a time the website went down after a deployment."**

> "First I check the load balancer — specifically the target health status. If all instances are unhealthy, I know the app failed to start or health checks are failing. Then I SSH into one of the instances and check the application logs to see the startup error. Common causes I've seen are wrong database connection strings, port mismatches between the app and the LB health check, or a failed database migration that left the schema in a bad state. Once I identify the cause I either fix and redeploy, or rollback using kubectl rollout undo or the ASG launch template version. To prevent this I'd recommend blue-green deployments and smoke tests in the pipeline so broken versions are caught before they reach production."
