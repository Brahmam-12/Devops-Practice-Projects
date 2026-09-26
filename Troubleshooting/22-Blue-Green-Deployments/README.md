# Scenario 22: Blue-Green Deployments

## What Is Blue-Green?

```
Two identical environments (Blue = current prod, Green = new version):

  Traffic → 100% Blue (v1)     Deploy new version to Green (v2)
  Traffic → 100% Blue (v1)     Test Green (v2) — smoke tests pass
  Traffic → 100% Green (v2)    Switch in seconds (DNS or LB swap)
  Traffic → 100% Green (v2)    Keep Blue (v1) running for 10 min
  Traffic → 100% Green (v2)    If bad: switch back to Blue (v1) in seconds

Benefits:
  Zero downtime deployment
  Instant rollback (just switch back)
  Green tested before users see it
```

---

## AWS Implementation

### Using ALB Target Groups (Zero Downtime)

```bash
# Blue Target Group = current production (v1)
# Green Target Group = new version (v2)

# Step 1: Deploy v2 to Green ASG (no traffic yet)
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name green-asg \
  --launch-template LaunchTemplateId=lt-xxx,Version=2

aws autoscaling start-instance-refresh --auto-scaling-group-name green-asg

# Step 2: Wait for Green instances to be healthy
aws elbv2 describe-target-health \
  --target-group-arn arn:...green-tg...

# Step 3: Run smoke tests against Green (not yet public)
curl -H "X-Environment: green" https://api.company.com/health

# Step 4: Switch traffic — change ALB listener to point to Green TG
aws elbv2 modify-listener \
  --listener-arn arn:aws:elasticloadbalancing:...:listener/... \
  --default-actions Type=forward,TargetGroupArn=arn:...green-tg...

# Step 5: Monitor for 10 minutes
# If error rate spikes:
aws elbv2 modify-listener \
  --listener-arn arn:... \
  --default-actions Type=forward,TargetGroupArn=arn:...blue-tg...
# Traffic back to Blue instantly

# Step 6: Scale down Blue once Green is stable
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name blue-asg \
  --desired-capacity 0
```

---

## Kubernetes Implementation

### Method 1: Two Deployments + Service Selector Switch

```yaml
# Blue deployment (v1) — running
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-blue
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: blue
  template:
    metadata:
      labels:
        app: myapp
        version: blue    # ← blue label
    spec:
      containers:
      - name: myapp
        image: myapp:v1

---
# Green deployment (v2) — new version
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-green
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
      version: green
  template:
    metadata:
      labels:
        app: myapp
        version: green   # ← green label
    spec:
      containers:
      - name: myapp
        image: myapp:v2

---
# Service — points to BLUE currently
apiVersion: v1
kind: Service
metadata:
  name: myapp-service
spec:
  selector:
    app: myapp
    version: blue   # ← change this to "green" to switch traffic
  ports:
  - port: 80
    targetPort: 8080
```

```bash
# Deploy Green (no traffic yet)
kubectl apply -f myapp-green-deployment.yaml

# Wait for Green to be ready
kubectl rollout status deployment/myapp-green -n production

# Run smoke tests against Green pods directly
GREEN_POD=$(kubectl get pods -n production -l version=green -o jsonpath='{.items[0].metadata.name}')
kubectl exec $GREEN_POD -n production -- curl -s http://localhost:8080/health

# Switch traffic — update Service selector to green
kubectl patch service myapp-service -n production \
  --patch '{"spec":{"selector":{"version":"green"}}}'

# Verify traffic is going to Green
kubectl get endpoints myapp-service -n production

# If problem — switch back to Blue in 1 command
kubectl patch service myapp-service -n production \
  --patch '{"spec":{"selector":{"version":"blue"}}}'

# After confirming Green is stable — delete Blue
kubectl delete deployment myapp-blue -n production
```

---

## Azure — App Service Deployment Slots

```bash
# Azure App Service has built-in Blue-Green via "slots"

# Create staging slot (Green)
az webapp deployment slot create \
  --resource-group myrg \
  --name myapp \
  --slot staging

# Deploy new version to staging slot
az webapp deploy \
  --resource-group myrg \
  --name myapp \
  --slot staging \
  --src-path myapp-v2.zip

# Test staging slot
curl https://myapp-staging.azurewebsites.net/health

# Swap slots (staging → production) — zero downtime
az webapp deployment slot swap \
  --resource-group myrg \
  --name myapp \
  --slot staging \
  --target-slot production

# If problem — swap back
az webapp deployment slot swap \
  --resource-group myrg \
  --name myapp \
  --slot staging \
  --target-slot production
```

---

## Troubleshooting Blue-Green Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| Green never healthy | App startup fails | Check Green pod logs |
| Traffic still hitting Blue after switch | DNS caching, connection keep-alive | Wait for TTL, force reconnect |
| Both environments receiving traffic | Partial switch, split traffic | Complete the switch |
| Database migration conflicts | Blue and Green share same DB | Schema must be backward compatible |

---

## Interview Answer

**Q: "How would you implement a blue-green deployment?"**

> "In Kubernetes I run two deployments — blue with the current version and green with the new version — both using the same labels except a version label. The Service selector points to blue initially. I deploy green with no traffic, run smoke tests directly against the green pods, then patch the Service selector to point to green. Traffic switches instantly. If something is wrong I patch the selector back to blue — rollback takes one command. In AWS I use two Target Groups behind one ALB and modify the listener to switch between them. The key requirement is that the database schema change is backward compatible — both v1 and v2 must work against the same database during and after the switch."
