# Scenario 15: Database Connectivity Failures

## Symptom
- App logs: "could not connect to server", "Connection refused", "too many connections"
- 500 errors from API — all requests that need DB are failing
- DB query latency spiked
- Alert: DB connection errors > threshold

---

## 1. Understand the Architecture

```
App → Connection Pool → DB (RDS / Azure SQL)

Connection pool:
  App maintains N open connections to DB at all times.
  On request: borrows connection from pool → query → returns connection.
  If pool exhausted (all connections in use): request WAITS or FAILS.

What breaks:
  DB is down           → all connections fail
  DB unreachable       → SG/NSG blocking port, wrong host, network issue
  Connection pool full → too many concurrent requests, pool undersized
  DB max_connections   → DB itself refuses new connections
  Credential wrong     → authentication failure
  SSL mismatch         → app requires SSL, DB not configured for it
```

---

## 2. Troubleshooting Strategy

### Step 1: Can the app reach the DB at all?

```bash
# Test connectivity from the app pod/VM
kubectl exec <app-pod> -n production -- \
  nc -zv db-hostname.postgres.database.azure.com 5432
# or for MySQL:
kubectl exec <app-pod> -n production -- \
  nc -zv db-hostname.mysql.database.azure.com 3306

# If connection refused → SG/NSG blocking port, or DB is down
# If timeout → network path issue (route, firewall, private endpoint)
# If connected → DB is reachable, issue is auth or app-level
```

---

### Step 2: Is the DB running?

**AWS RDS:**
```bash
aws rds describe-db-instances \
  --db-instance-identifier mydb \
  --query "DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address}"

# Status: available    → DB is running
# Status: stopped      → DB was manually stopped (dev/test cost saving)
# Status: starting     → DB is starting, wait
# Status: failed       → DB needs manual intervention

# Start a stopped RDS
aws rds start-db-instance --db-instance-identifier mydb
```

**Azure SQL:**
```
Portal → Azure SQL → server → database → Overview → Status
# Or:
az sql db show --resource-group myrg --server myserver --name mydb \
  --query "status"
```

---

### Step 3: Check Security Group / NSG

```bash
# AWS — does the SG allow inbound on DB port from app SG?
aws ec2 describe-security-groups --group-ids sg-db-xxxx \
  --query "SecurityGroups[0].IpPermissions"

# Look for: FromPort: 5432 (PostgreSQL) or 3306 (MySQL)
# Source: sg-app-xxxx (the app security group)
# If missing → add inbound rule

# Azure — check NSG on DB subnet
az network nsg rule list \
  --resource-group myrg \
  --nsg-name db-subnet-nsg \
  --output table
# Look for rule allowing TCP 5432/3306 from app subnet CIDR
```

---

### Step 4: Check connection pool exhaustion

```bash
# App logs show: "connection pool exhausted" or "too many clients already"

# Check how many DB connections exist
kubectl exec <app-pod> -n production -- \
  psql -h db-host -U dbuser -c "SELECT count(*), state FROM pg_stat_activity GROUP BY state;"

# Expected: connection count = pool size × number of pods
# If count >> expected → connection leak (connections not being closed)

# Check DB max_connections limit
kubectl exec <app-pod> -n production -- \
  psql -h db-host -U dbuser -c "SHOW max_connections;"

# If current connections ≈ max_connections → DB refusing new connections
```

---

### Step 5: Check credentials

```bash
# Test credentials manually
kubectl exec <app-pod> -n production -- \
  psql -h db-host -U dbuser -d dbname -c "SELECT 1;"

# If: "password authentication failed for user"
#   → wrong password in secret
kubectl get secret db-credentials -n production -o jsonpath='{.data.password}' | base64 -d

# Compare with actual DB password
# Rotate password if wrong:
kubectl patch secret db-credentials -n production \
  --patch '{"data":{"password":"'$(echo -n "newpassword" | base64)'"}}'
# Then restart app pods to pick up new secret
kubectl rollout restart deployment/myapp -n production
```

---

## 4. Root Cause + Fix

| Root Cause | Evidence | Fix |
|-----------|----------|-----|
| DB stopped | RDS status: stopped | Start DB, alert on DB stop |
| SG blocking port | `nc` connection refused | Add inbound rule to DB SG |
| Connection pool exhausted | Pool exhausted error in logs | Increase pool size, fix connection leaks |
| DB max_connections hit | `pg_stat_activity` count = max | Increase max_connections, use PgBouncer |
| Wrong credentials | authentication failed | Fix secret, rotate password |
| SSL required | SSL error in logs | Add SSL params to connection string |

---

## Interview Answer

**Q: "App can't connect to database — how do you debug?"**

> "I work layer by layer. First I test basic connectivity with nc or telnet from the app pod to the DB host and port — connection refused means the DB is down or a firewall is blocking it. If connectivity works, I test authentication by manually connecting with the DB credentials. If that fails, the secret has the wrong password. If connectivity and auth both work, the issue is at the connection pool level — I check how many active connections exist in the DB and compare to max_connections. Connection pool exhaustion under load is very common — the fix is increasing pool size or using a connection pooler like PgBouncer that multiplexes many app connections into fewer DB connections."
