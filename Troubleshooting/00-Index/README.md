# DevOps Troubleshooting — 25 Production Scenarios

## How to Use This

Every scenario follows the same four-step framework:

```
1. Understand the Architecture   → How does the request flow? Which components?
2. Identify the Symptom          → What is broken? What does the user see?
3. Troubleshooting Strategy      → What do we check? Why? What command? What output?
4. Root Cause Analysis           → Confirm cause → Fix → Prevent
```

Every check answers three questions:
- **What** are you checking?
- **Why** are you checking it?
- **What conclusion** can you draw from the output?

---

## The 25 Scenarios

| # | Scenario | Category | File |
|---|----------|----------|------|
| 01 | Website down after deployment | Deployment | [01-Website-Down](../01-Website-Down-After-Deployment/) |
| 02 | Pod CrashLoopBackOff | Kubernetes | [02-CrashLoopBackOff](../02-Pod-CrashLoopBackOff/) |
| 03 | Health check failures | Networking | [03-Health-Check-Failures](../03-Health-Check-Failures/) |
| 04 | 502/503/504 errors | Networking | [04-502-503-504-Errors](../04-502-503-504-Errors/) |
| 05 | SSL/TLS certificate issues | Security | [05-SSL-TLS-Issues](../05-SSL-TLS-Certificate-Issues/) |
| 06 | DNS resolution failures | Networking | [06-DNS-Failures](../06-DNS-Resolution-Failures/) |
| 07 | High CPU or memory usage | Performance | [07-High-CPU-Memory](../07-High-CPU-Memory-Usage/) |
| 08 | OOMKilled pods | Kubernetes | [08-OOMKilled](../08-OOMKilled-Pods/) |
| 09 | Persistent Volume issues | Kubernetes | [09-PV-Issues](../09-Persistent-Volume-Issues/) |
| 10 | CI/CD pipeline failures | CI/CD | [10-CICD-Failures](../10-CICD-Pipeline-Failures/) |
| 11 | Docker image build failures | Docker | [11-Docker-Build-Failures](../11-Docker-Image-Build-Failures/) |
| 12 | Terraform state conflicts | IaC | [12-Terraform-State](../12-Terraform-State-Conflicts/) |
| 13 | Node NotReady | Kubernetes | [13-Node-NotReady](../13-Node-NotReady/) |
| 14 | Autoscaling not working | Scaling | [14-Autoscaling-Issues](../14-Autoscaling-Not-Working/) |
| 15 | Database connectivity failures | Database | [15-DB-Connectivity](../15-Database-Connectivity-Failures/) |
| 16 | Secret and ConfigMap issues | Kubernetes | [16-Secrets-ConfigMap](../16-Secret-ConfigMap-Issues/) |
| 17 | Networking and CNI problems | Networking | [17-CNI-Problems](../17-Networking-CNI-Problems/) |
| 18 | Ingress troubleshooting | Kubernetes | [18-Ingress](../18-Ingress-Troubleshooting/) |
| 19 | IAM/RBAC permission issues | Security | [19-IAM-RBAC](../19-IAM-RBAC-Permission-Issues/) |
| 20 | Monitoring and alert investigations | Observability | [20-Monitoring-Alerts](../20-Monitoring-Alert-Investigations/) |
| 21 | Disaster recovery and backups | DR | [21-Disaster-Recovery](../21-Disaster-Recovery-Backups/) |
| 22 | Blue-Green deployments | Deployment | [22-Blue-Green](../22-Blue-Green-Deployments/) |
| 23 | Canary deployments | Deployment | [23-Canary](../23-Canary-Deployments/) |
| 24 | Multi-region failover | DR | [24-Multi-Region-Failover](../24-Multi-Region-Failover/) |
| 25 | Complete end-to-end production outage | Incident | [25-Production-Outage](../25-Production-Outage-Investigation/) |

---

## Troubleshooting Mindset

```
NEVER do this:                      ALWAYS do this:
────────────────────────────────    ──────────────────────────────────────────
Randomly restart pods/services      Collect evidence first, then act
Assume the problem                  Confirm with data (logs, metrics, events)
Fix without understanding why       Understand root cause before applying fix
Skip documentation                  Note everything you checked and found
Guess the solution                  Follow the signal: logs → metrics → traces
```

## Interview Tip

When asked "how would you debug X", answer in this pattern:

```
"First I would understand the request flow to know which components are involved.
 Then I would look at [first signal] because [reason].
 If that's healthy, I would check [next signal] because [reason].
 If I see [specific output], that tells me [conclusion].
 The most common root causes I've seen are [A], [B], [C].
 To prevent this I would [prevention measure]."
```
