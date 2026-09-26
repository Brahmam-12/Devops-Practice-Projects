# Scenario 05: SSL/TLS Certificate Issues

## Symptom
- Browser shows: "Your connection is not private" / NET::ERR_CERT_DATE_INVALID
- `curl` returns: SSL certificate problem: certificate has expired
- HTTPS stops working but HTTP works
- Alert fires: certificate expiry
- Webhook/API calls from services fail with SSL errors

---

## 1. Understand the Architecture

```
Where SSL certificates live:

Option A — Certificate on the Load Balancer (most common in cloud):
  Client → HTTPS → ALB / Azure App Gateway (SSL termination here)
                         ↓ HTTP (unencrypted internally)
                    Backend EC2 / VM / Pod

Option B — Certificate on the app (end-to-end encryption):
  Client → HTTPS → LB (pass-through) → HTTPS → Backend app

Option C — Certificate on Ingress (Kubernetes):
  Client → HTTPS → Ingress Controller (cert-manager / k8s secret)
                         ↓ HTTP internally
                    Backend pods

Certificate issues:
  ├── Expired certificate      → browser error, services reject connection
  ├── Wrong domain (mismatch)  → browser warns, cert is for different domain
  ├── Self-signed cert         → not trusted by browsers or services
  └── Missing intermediate CA  → chain incomplete, some clients reject it
```

---

## 2. Identify the Symptom

```bash
# Check certificate details from command line
curl -vI https://yourdomain.com 2>&1 | grep -E "expire|subject|issuer|SSL"

# Or use openssl for full details
echo | openssl s_client -connect yourdomain.com:443 -servername yourdomain.com 2>/dev/null \
  | openssl x509 -noout -dates -subject -issuer

# Output:
# notBefore=Jun 24 00:00:00 2025 GMT
# notAfter=Jun 24 23:59:59 2026 GMT   ← expired? this is the expiry date
# subject=CN = yourdomain.com
# issuer=CN = Let's Encrypt Authority X3

# Check days remaining
echo | openssl s_client -connect yourdomain.com:443 2>/dev/null \
  | openssl x509 -noout -enddate \
  | sed 's/notAfter=//'
```

---

## 3. Troubleshooting Strategy

### Step 1: Is the certificate expired?
**What:** Check the certificate expiry date.
**Why:** Most SSL issues are simply expired certificates.

```bash
# Quick check
echo | openssl s_client -connect yourdomain.com:443 2>/dev/null \
  | openssl x509 -noout -enddate

# notAfter=Jun 24 23:59:59 2026 GMT
# If this date is in the past → EXPIRED

# Check multiple services
for domain in api.company.com app.company.com admin.company.com; do
  echo -n "$domain: "
  echo | openssl s_client -connect $domain:443 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null || echo "CONNECTION FAILED"
done
```

---

### Step 2: Is the domain name correct on the certificate?
**What:** Does the certificate cover the domain users are accessing?
**Why:** Common after migrations — old cert valid, but for different domain.

```bash
echo | openssl s_client -connect yourdomain.com:443 -servername yourdomain.com 2>/dev/null \
  | openssl x509 -noout -subject -subj_hash

# subject=CN = yourdomain.com
# OR: subject=CN = *.yourdomain.com   ← wildcard covers subdomains

# Check Subject Alternative Names (SANs) — modern certs list all covered domains
echo | openssl s_client -connect yourdomain.com:443 2>/dev/null \
  | openssl x509 -noout -text | grep -A 3 "Subject Alternative Name"

# DNS:yourdomain.com, DNS:www.yourdomain.com, DNS:api.yourdomain.com
# If your domain is NOT in this list → domain mismatch error
```

---

### Step 3: AWS — Check ACM certificate status
**What:** Is the certificate in ACM valid and attached to the LB?
**Why:** ACM certs auto-renew, but renewal can fail if DNS validation records were deleted.

```bash
# List all certificates
aws acm list-certificates --certificate-statuses ISSUED PENDING_VALIDATION FAILED EXPIRED

# Check specific cert status
aws acm describe-certificate --certificate-arn arn:aws:acm:us-east-1:...

# Key fields:
# Status: ISSUED          → valid
# Status: EXPIRED         → expired (ACM doesn't auto-delete expired certs)
# Status: PENDING_VALIDATION → renewal is waiting for DNS/email validation
# RenewalSummary.RenewalStatus: SUCCESS / FAILED / PENDING_AUTO_RENEWAL

# If PENDING_VALIDATION:
# DomainValidationOptions → shows the CNAME record you need in Route 53
aws acm describe-certificate --certificate-arn arn:... \
  --query "Certificate.DomainValidationOptions"
```

**Check the CNAME is in Route 53:**
```bash
aws route53 list-resource-record-sets \
  --hosted-zone-id Z123456 \
  --query "ResourceRecordSets[?Type=='CNAME']"
```

---

### Step 4: Azure — Check App Gateway / Front Door certificate
**What:** Is the certificate attached to the HTTPS listener still valid?
**Why:** Azure does not auto-renew custom uploaded certificates — only managed certs.

```
Portal → Application Gateway → Listeners → select HTTPS listener
       → SSL Certificate → check expiry date

Portal → Front Door → Domains → HTTPS settings
       → Certificate type: AFD managed (auto-renews) vs Custom (manual)
```

**Azure Key Vault certificates (auto-renew):**
```bash
# Check cert expiry in Key Vault
az keyvault certificate show \
  --vault-name mykeyvault \
  --name mycert \
  --query "{Expires:attributes.expires, Status:policy.x509CertificateProperties.validityInMonths}"

# Check if cert is linked to App Gateway
az network application-gateway ssl-cert list \
  --resource-group myrg \
  --gateway-name myappgw
```

---

### Step 5: Kubernetes — cert-manager certificate status
**What:** Is the certificate object valid and the secret populated?
**Why:** cert-manager automates Let's Encrypt, but challenges can fail.

```bash
# List all certificates
kubectl get certificates -A

# NAME         READY   SECRET              AGE
# myapp-cert   True    myapp-tls-secret    30d   ← READY True = valid
# myapp-cert   False   myapp-tls-secret    1h    ← READY False = problem

# Get details on a failing cert
kubectl describe certificate myapp-cert -n production

# Look at Events and Conditions:
# Ready: False
# Reason: Failed to obtain certificate, error: acme: error: 403
# Message: Domain validation failed

# Check the CertificateRequest
kubectl get certificaterequest -n production
kubectl describe certificaterequest myapp-cert-xxxxx -n production

# Check ACME challenge
kubectl get challenges -n production
kubectl describe challenge <challenge-name> -n production
# Reason might be: DNS-01 challenge failed, HTTP-01 challenge failed
```

**Common cert-manager issues:**
```bash
# HTTP-01 challenge fails if port 80 is blocked
# DNS-01 challenge fails if API token for DNS provider is wrong

# Check Ingress has correct annotation
kubectl get ingress myapp -n production -o yaml | grep cert-manager
# Should have: cert-manager.io/cluster-issuer: letsencrypt-prod

# Force certificate renewal
kubectl delete certificate myapp-cert -n production
# cert-manager will recreate and re-issue
```

---

## 4. Root Cause Analysis + Fix

| Root Cause | Evidence | Fix |
|-----------|----------|-----|
| Certificate expired | `openssl` shows past date | Renew/reissue certificate |
| ACM renewal failed | ACM status: PENDING_VALIDATION | Add CNAME record back to Route 53 |
| cert-manager challenge failed | `kubectl describe challenge` shows 403 | Fix ingress, check port 80 open |
| Domain mismatch | SAN list doesn't include the domain | Issue cert for correct domain |
| Wrong cert attached to LB | LB showing old cert | Update LB listener with new cert ARN |
| Self-signed cert in production | Issuer = your org, not trusted CA | Replace with CA-signed cert |

---

## 5. Fixes

**AWS ACM — Trigger re-validation:**
```bash
# The CNAME record for validation was deleted — add it back
# Get the validation CNAME
aws acm describe-certificate --certificate-arn arn:... \
  --query "Certificate.DomainValidationOptions[0].ResourceRecord"

# Output:
# { "Name": "_abc123.yourdomain.com", "Type": "CNAME", "Value": "_def456.acm-validations.aws" }
# Add this to Route 53 → ACM will auto-validate and renew
```

**Update ALB listener with new certificate:**
```bash
aws elbv2 modify-listener \
  --listener-arn arn:aws:elasticloadbalancing:... \
  --certificates CertificateArn=arn:aws:acm:us-east-1:...:certificate/new-cert-id
```

**Kubernetes — force cert renewal:**
```bash
kubectl delete secret myapp-tls-secret -n production
kubectl delete certificate myapp-cert -n production
# cert-manager recreates both automatically
```

---

## 6. Prevention

| Measure | What it prevents |
|---------|-----------------|
| Certificate expiry alert at 30 days | Surprise expiry |
| ACM managed certs (not self-managed) | Manual renewal forgotten |
| cert-manager with auto-renew | Kubernetes cert expiry |
| Monitor cert expiry with Prometheus / Azure Monitor | Late discovery |
| DNS validation CNAME kept in Route 53 permanently | ACM renewal failure |
| Test HTTPS after every deploy | Catching cert issues pre-production |

---

## Interview Answer

**Q: "HTTPS stopped working — users see certificate error. How do you debug?"**

> "First I check the certificate expiry using openssl s_client — if it's expired, that's the most common cause. Then I check where the certificate lives: on the load balancer (ACM in AWS), on the Ingress (cert-manager in Kubernetes), or uploaded to Azure App Gateway. In AWS, ACM certificates renew automatically but the renewal needs DNS validation — if the CNAME record was deleted from Route 53, renewal fails and the cert expires. In Kubernetes, I'd check kubectl get certificates and kubectl describe challenge to see if the ACME challenge is failing. The fix depends on the root cause — add back the validation DNS record, force a cert-manager renewal, or upload a new certificate to the load balancer."
