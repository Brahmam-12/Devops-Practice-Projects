# Scenario 21: Disaster Recovery and Backups

## Symptom
- Region outage — all resources in us-east-1 unavailable
- RDS database accidentally deleted
- Kubernetes etcd corrupted
- Storage account deleted
- Entire resource group deleted

---

## 1. Understand the Architecture

```
DR Strategy levels (RPO = Recovery Point Objective, RTO = Recovery Time Objective):

Active-Active    → traffic split across 2 regions. RPO: 0. RTO: seconds.
Active-Passive   → primary active, secondary warm standby. RPO: minutes. RTO: minutes.
Backup-Restore   → primary active, periodic backups. RPO: hours. RTO: hours.

What you back up:
  Database     → automated snapshots (RDS) / point-in-time restore (Azure SQL)
  Files        → Azure Blob / S3 with versioning + cross-region replication
  Kubernetes   → etcd backup, PV snapshots (Velero)
  Config/IaC   → Terraform state in versioned Blob / S3
  Secrets      → Key Vault backup, AWS Secrets Manager replication
```

---

## 2. Troubleshooting — Restore Scenarios

### Scenario A: Restore RDS from snapshot

```bash
# List available snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier mydb \
  --query "DBSnapshots[*].{Id:DBSnapshotIdentifier,Time:SnapshotCreateTime,Status:Status}" \
  --output table

# Restore to new RDS instance from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier mydb-restored \
  --db-snapshot-identifier mydb-2026-06-26-00-00 \
  --db-instance-class db.t3.medium \
  --no-multi-az

# Point app to new DB endpoint (update secret)
NEW_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier mydb-restored \
  --query "DBInstances[0].Endpoint.Address" -o tsv)

kubectl patch secret db-credentials -n production \
  --patch "{\"data\":{\"DB_HOST\":\"$(echo -n $NEW_ENDPOINT | base64)\"}}"
kubectl rollout restart deployment/myapp -n production
```

---

### Scenario B: Azure SQL Point-in-Time Restore

```bash
# Azure SQL supports restore to any point within retention period (up to 35 days)
az sql db restore \
  --resource-group myrg \
  --server myserver \
  --name mydb-restored \
  --source-database-name mydb \
  --time "2026-06-25T18:00:00Z"   # restore to 6pm yesterday

# After restore: update connection string in Key Vault / Secret
```

---

### Scenario C: Restore Kubernetes workloads with Velero

```bash
# List available backups
velero backup get

# NAME                 STATUS     CREATED                EXPIRES
# daily-2026-06-25     Completed  2026-06-25 02:00:00    6d

# Restore entire namespace
velero restore create --from-backup daily-2026-06-25 \
  --include-namespaces production

# Restore specific resources only
velero restore create --from-backup daily-2026-06-25 \
  --include-resources deployments,services,configmaps \
  --include-namespaces production

# Check restore status
velero restore describe <restore-name>
velero restore logs <restore-name>
```

---

### Scenario D: Restore Azure Blob (soft delete)

```bash
# List deleted containers (30-day retention)
az storage container list \
  --account-name mystorage \
  --include-deleted \
  --query "[?deleted].{Name:name,DeletedTime:properties.deletedTime}"

# Restore deleted container
az storage container restore \
  --account-name mystorage \
  --name mycontainer \
  --deleted-version <version-id>

# Restore deleted blob
az storage blob undelete \
  --account-name mystorage \
  --container-name mycontainer \
  --name myblob
```

---

### Scenario E: Region failover (Active-Passive)

```bash
# Step 1: Check if primary is really down (don't failover on false alarm)
aws ec2 describe-availability-zones --region us-east-1

# Step 2: Promote RDS read replica in secondary region
aws rds promote-read-replica \
  --db-instance-identifier mydb-replica-us-west-2 \
  --region us-west-2

# Step 3: Update Route 53 to point to secondary region LB
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123 \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.company.com",
        "Type": "A",
        "AliasTarget": {
          "DNSName": "secondary-alb.us-west-2.elb.amazonaws.com",
          "HostedZoneId": "Z1H1FL5HABSF5",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'

# Step 4: Scale up secondary region ASG
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name my-asg-us-west-2 \
  --desired-capacity 10 \
  --region us-west-2
```

---

## 3. Prevention — What You Must Have Before Disaster

| What | How | Frequency |
|------|-----|-----------|
| RDS automated snapshots | Enabled, 7-30 day retention | Daily (automatic) |
| Cross-region RDS replica | RDS → Replication → Add read replica | Real-time |
| Velero backups | Scheduled daily backup to S3/Azure Blob | Daily |
| Blob versioning + GRS | Enable on critical storage accounts | Continuous |
| Terraform state in ZRS Blob | ZRS + versioning | Per apply |
| DR runbook | Written + tested quarterly | Quarterly |
| RTO/RPO targets documented | Agreed with business | Before incident |

---

## Interview Answer

**Q: "Your primary region goes down — what do you do?"**

> "First I confirm it's a real region outage and not a false alarm — I check the cloud provider's status page and verify multiple services are affected. Then I execute the DR runbook: promote the RDS read replica in the secondary region to primary, update Route 53 to point to the secondary region's load balancer, and scale up the secondary ASG to handle production traffic. The key is having all of this prepared and tested in advance — a DR plan you've never practiced will fail when you need it most. After the primary region recovers, we do a controlled failback rather than immediately switching — validate everything is working in primary first, then shift traffic gradually."
