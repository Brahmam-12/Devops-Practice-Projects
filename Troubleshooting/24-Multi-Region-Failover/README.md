# Scenario 24: Multi-Region Failover

## What Is Multi-Region Failover?

```
Active-Active:   Both regions serve traffic simultaneously (split by geography or load)
Active-Passive:  Primary handles all traffic; secondary is warm standby, activated on failure

Failover triggers:
  Primary region health check fails (Route 53 / Traffic Manager)
  Manual decision during planned maintenance
  Partial outage (DB down in primary, failover DB only)
```

---

## Architecture

```
Users
  │
  ▼
Route 53 / Azure Traffic Manager / Front Door (global DNS with health checks)
  │                │
  │ Primary        │ Secondary (standby)
  ▼                ▼
us-east-1          us-west-2
├── ALB            ├── ALB (scaled down or warm)
├── EC2 ASG        ├── EC2 ASG
├── RDS Primary    ├── RDS Read Replica (promoted on failover)
└── ElastiCache    └── ElastiCache (standalone or replica)
```

---

## Troubleshooting — When to Failover and When Not To

```
Confirm it's a real region issue:
  ✅ AWS status page shows us-east-1 outage
  ✅ Multiple services in region are down (EC2, RDS, ALB)
  ✅ Your monitoring from outside us-east-1 confirms unreachable

Don't failover if:
  ❌ One service is down (fix it in primary, don't failover whole region)
  ❌ Status page shows no issues (could be your app, not the region)
  ❌ Brief network blip (wait 5 minutes before deciding)

Failover is expensive:
  Data in transit may be lost (RPO)
  DB replication lag means seconds/minutes of data loss
  Cold secondary takes time to warm up (RTO)
```

---

## AWS — Failover Implementation

### Route 53 Health Check + Failover Routing

```bash
# Route 53 Failover record set:
# Primary: us-east-1 ALB → health check monitors endpoint
# Secondary: us-west-2 ALB → activates if primary health check fails

# Create health check for primary
aws route53 create-health-check \
  --caller-reference $(date +%s) \
  --health-check-config '{
    "IPAddress": "ALB-IP",
    "Port": 443,
    "Type": "HTTPS",
    "ResourcePath": "/health",
    "FailureThreshold": 3,
    "RequestInterval": 30
  }'

# Associate health check with Primary record set
# Primary: Failover=PRIMARY, HealthCheckId=xxx
# Secondary: Failover=SECONDARY (no health check needed — activates automatically)
```

### Manual Failover Execution

```bash
# Step 1: Promote RDS read replica in secondary region
aws rds promote-read-replica \
  --db-instance-identifier mydb-replica \
  --region us-west-2

# Wait for promotion
aws rds describe-db-instances \
  --db-instance-identifier mydb-replica \
  --region us-west-2 \
  --query "DBInstances[0].DBInstanceStatus"
# Wait until: available

# Step 2: Scale up secondary ASG
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name my-asg-us-west-2 \
  --desired-capacity 6 \
  --region us-west-2

# Step 3: Update app config to point to new DB
aws secretsmanager update-secret \
  --secret-id myapp/db-url \
  --secret-string "postgresql://user:pass@mydb-replica.us-west-2.rds.amazonaws.com/mydb" \
  --region us-west-2

# Step 4: If Route 53 hasn't auto-failed over, force it
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123 \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.company.com",
        "Type": "A",
        "Failover": "SECONDARY",
        "TTL": 60,
        "AliasTarget": {"DNSName": "secondary-alb.us-west-2.elb.amazonaws.com", ...}
      }
    }]
  }'
```

---

## Azure — Failover with Traffic Manager

```bash
# Azure Traffic Manager does automatic failover based on endpoint health

# Check Traffic Manager profile
az network traffic-manager profile show \
  --resource-group myrg \
  --name my-traffic-manager

# Check endpoint health
az network traffic-manager endpoint show \
  --resource-group myrg \
  --profile-name my-traffic-manager \
  --type azureEndpoints \
  --name primary-endpoint

# Manual failover — disable primary endpoint
az network traffic-manager endpoint update \
  --resource-group myrg \
  --profile-name my-traffic-manager \
  --type azureEndpoints \
  --name primary-endpoint \
  --endpoint-status Disabled

# Traffic Manager now routes 100% to secondary endpoint
```

---

## After Failover — What to Do

```bash
# 1. Confirm secondary is handling traffic correctly
curl https://api.company.com/health
# Check response header: X-Region: us-west-2

# 2. Monitor error rates closely for 15 minutes
# Secondary may have different cache state, different data

# 3. Communicate to team and stakeholders
# "Primary region outage at 14:30. Failover to us-west-2 at 14:45.
#  Estimated data loss: ~2 minutes (RDB replication lag).
#  All services operational."

# 4. When primary recovers — Failback (controlled)
# Don't rush failback — validate primary is stable first
# Sync data changes made in secondary back to primary
# Gradually shift traffic back (treat failback like a canary deploy)
```

---

## Interview Answer

**Q: "How would you handle a full region failover?"**

> "First I confirm it's actually a region issue — I check the cloud provider's status page and verify it's not just our app. False positives cost more than a brief outage. Once confirmed, I promote the read replica in the secondary region to a standalone writable DB, then scale up the secondary ASG, then update DNS to point to the secondary region. Route 53 with health checks handles this automatically if configured correctly. After failover I monitor the secondary for 15 minutes to confirm it's handling traffic correctly. For failback, I treat it like a canary deploy — gradually shift traffic back to primary rather than all at once, because primary may have different cache or connection state."
