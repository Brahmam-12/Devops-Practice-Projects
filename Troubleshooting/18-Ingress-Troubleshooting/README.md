# Scenario 18: Ingress Troubleshooting

## Symptom
- HTTPS/HTTP requests returning 404 (but service is running)
- Ingress created but no external IP assigned
- TLS termination not working
- Path-based routing sending to wrong service
- Rewrite rules not working

---

## 1. Understand the Architecture

```
Client → DNS → LoadBalancer IP (nginx-ingress / ALB Ingress / Azure App Gateway)
              → Ingress Controller (reads Ingress rules)
              → routes to correct Service based on host/path
              → Service → Pod

Ingress resource = rules (which host + path → which service)
Ingress Controller = the actual process implementing those rules

If Ingress resource exists but controller is down → no routing
If controller is up but rules are wrong → 404 or wrong service
```

---

## 2. Troubleshooting Strategy

### Step 1: Check Ingress has an external IP

```bash
kubectl get ingress -n production

# NAME     CLASS   HOSTS              ADDRESS         PORTS   AGE
# myapp    nginx   app.company.com    203.0.113.45    80,443  5d  ← ADDRESS assigned
# myapp    nginx   app.company.com    <none>          80,443  5m  ← NO ADDRESS — problem

# If no address:
# 1. Ingress controller is not installed
# 2. LoadBalancer service for controller has no external IP
# 3. Wrong IngressClass name
```

---

### Step 2: Check Ingress controller is running

```bash
# Nginx Ingress
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx   # service type LoadBalancer must have EXTERNAL-IP

# AWS ALB Ingress Controller (AWS Load Balancer Controller)
kubectl get pods -n kube-system | grep aws-load-balancer

# Azure — AGIC (Application Gateway Ingress Controller)
kubectl get pods -n kube-system | grep ingress

# Check controller logs for errors
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller | tail -50
# Look for: "Error obtaining Endpoints" → backend service not found
#           "service not found"          → Ingress references wrong service name
```

---

### Step 3: Verify Ingress rules are correct

```bash
kubectl describe ingress myapp -n production

# Look at Rules section:
# Host: app.company.com
# Path: /api  → service: api-service:8080  ← service name and port
# Path: /     → service: web-service:80

# Common mistakes:
# Service name typo (case sensitive)
# Wrong port (service port not matching)
# Path regex wrong (/ vs /*)
# Missing pathType: Prefix vs Exact

# Verify the backend service exists
kubectl get svc api-service -n production
kubectl get endpoints api-service -n production
# Endpoints must show pod IPs — if <none>, pods not matching selector
```

---

### Step 4: Test with curl

```bash
# Test with host header (bypass DNS)
curl -v -H "Host: app.company.com" http://<ingress-external-ip>/api/health

# Test specific path routing
curl -v -H "Host: app.company.com" http://<ingress-external-ip>/api/
curl -v -H "Host: app.company.com" http://<ingress-external-ip>/web/

# If /api returns 404 but /web works → path routing issue in Ingress
```

---

### Step 5: TLS not working

```bash
# Check TLS secret exists and has correct keys
kubectl get secret myapp-tls -n production
kubectl describe secret myapp-tls -n production
# Data must have: tls.crt and tls.key

# Check Ingress TLS config
kubectl get ingress myapp -n production -o yaml | grep -A 5 tls:
# tls:
# - hosts:
#   - app.company.com
#   secretName: myapp-tls   ← must match the secret name exactly

# Check cert is valid for the host
kubectl get secret myapp-tls -n production \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -dates
```

---

## 4. Root Cause + Fix

| Root Cause | Evidence | Fix |
|-----------|----------|-----|
| No external IP | Ingress ADDRESS is empty | Install/fix Ingress controller, check LB |
| Wrong IngressClass | Controller ignoring Ingress | Add `ingressClassName: nginx` to spec |
| Service name wrong | Controller logs: service not found | Fix service name in Ingress rules |
| No endpoints | `kubectl get ep` shows none | Fix pod selector in Service |
| TLS secret missing | Secret not found | Create TLS secret or use cert-manager |
| Path not matching | 404 on specific paths | Fix pathType: Prefix and path value |

---

## Interview Answer

**Q: "Ingress created but requests are returning 404 — how do you debug?"**

> "First I check kubectl describe ingress to see the Rules — verifying the service name, port, and path match exactly what's configured. Then I check that the backend service exists and has endpoints (kubectl get endpoints). If the service has no endpoints, the pod labels don't match the service selector. If the service is fine, I check the Ingress controller logs for errors. A very common cause of 404 is the IngressClass not set — if the controller is filtering by class and the Ingress doesn't specify the right class, the controller simply ignores the resource. I also test with curl using the Host header to bypass DNS and isolate the routing logic."
