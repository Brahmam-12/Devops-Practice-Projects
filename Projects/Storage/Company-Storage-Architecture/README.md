# Company Azure Storage Architecture

## What This Project Is

This project builds a **single, production-grade Azure Storage Account** that covers every storage need a company has — the same way real companies set it up in Azure.

Instead of creating separate storage accounts for every purpose (which is wasteful and hard to manage), one well-configured storage account runs all four Azure storage services inside it:

```
Storage Account: companystorage (one account, four services inside)
├── Blob Storage     → files, artifacts, backups, logs, Terraform state
├── Azure Files      → shared network drives (SMB) for VMs
├── Table Storage    → simple NoSQL key-value data
└── Queue Storage    → async message passing between services
```

---

## Architecture Overview

```
                    ┌──────────────────────────────────────────────────────────────┐
                    │          Storage Account: companystorage (Standard ZRS)      │
                    │                                                               │
                    │  ┌─── BLOB SERVICE ──────────────────────────────────────┐  │
                    │  │  build-artifacts/  Hot→Cool(30d)→Archive(90d)→Del(1yr)│  │
                    │  │  app-logs/         Hot→Cool(7d)→Archive(30d)→Del(90d) │  │
                    │  │  db-backups/       Hot→Cool(30d)→Archive(90d) NO DEL  │  │
                    │  │  terraform-state/  Versioned + Private Endpoint 🔒     │  │
                    │  │  temp/             Delete after 3 days                 │  │
                    │  └───────────────────────────────────────────────────────┘  │
                    │                                                               │
                    │  ┌─── AZURE FILES SERVICE ────────────────────────────────┐  │
                    │  │  devops-configs  (SMB 10 GiB) — shared VM configs      │  │
                    │  │  sensitive-data  (SMB  5 GiB) — Private Endpoint 🔒    │  │
                    │  └───────────────────────────────────────────────────────┘  │
                    │                                                               │
                    │  ┌─── TABLE STORAGE ──────────────────────────────────────┐  │
                    │  │  DeploymentLogs  — event tracking per deploy            │  │
                    │  │  FeatureFlags    — on/off switches for features         │  │
                    │  └───────────────────────────────────────────────────────┘  │
                    │                                                               │
                    │  ┌─── QUEUE STORAGE ──────────────────────────────────────┐  │
                    │  │  deployment-jobs   — CI/CD async job triggers           │  │
                    │  │  notifications     — post-deploy alert messages         │  │
                    │  └───────────────────────────────────────────────────────┘  │
                    │                                                               │
                    │  Network: Deny public access. Allow only from company VNet  │
                    │  Private Endpoints: blob service 🔒 + file service 🔒       │
                    └──────────────────────────────────────────────────────────────┘
                                              │
                              ┌───────────────┴──────────────┐
                              │    company-vnet 10.0.0.0/16   │
                              │  app-subnet    10.0.1.0/24    │ ← VMs + AKS live here
                              │  pep-subnet    10.0.2.0/24    │ ← Private endpoint NICs
                              └──────────────────────────────┘
```

---

## What Each Service Is — Simple Explanation

### Blob Storage
Stores **any file** — there is no structure, no schema, no relationships. Just put a file in, get it back by name.

```
Real files stored in Blob:
  myapp-v2.3.zip          ← build artifact from CI/CD pipeline
  2026-06-24-db.bak       ← database backup
  prod.tfstate            ← Terraform state
  nginx-error-2026-06.log ← rotated application log
  startup-script.sh       ← VM cloud-init script
```

**DevOps uses Blob for:** anything that is a file and needs to be stored reliably.

---

### Azure Files
A **network drive** you mount on a VM. Once mounted, the VM treats it like a local folder — `ls`, `cat`, `cp` all work. But the data actually lives in Azure and every VM that mounts the same share sees the same files.

```
Without Azure Files:          With Azure Files (devops-configs share mounted):
VM-1: /etc/app/config.json    VM-1 → /mnt/configs/config.json  ─┐
VM-2: /etc/app/config.json    VM-2 → /mnt/configs/config.json  ─┤→ same file in Azure
VM-3: /etc/app/config.json    VM-3 → /mnt/configs/config.json  ─┘
(3 separate files, drift)     (1 file, all VMs see same content)
```

**DevOps uses Azure Files for:** shared config files, shared certificates, app logs collected in one place, legacy apps that need a network drive.

---

### Table Storage
A **NoSQL key-value store**. No joins, no complex queries — just rows of data with a PartitionKey and RowKey. Very cheap and fast for simple lookups.

```
Table: DeploymentLogs
PartitionKey    RowKey              Status    Deployed_by   Duration
────────────────────────────────────────────────────────────────────
prod            2026-06-24T10:00   Success   github-actions  4m32s
prod            2026-06-23T14:30   Failed    github-actions  1m10s
dev             2026-06-24T09:00   Success   john@company    2m05s

Table: FeatureFlags
PartitionKey    RowKey              Enabled   RolloutPct
────────────────────────────────────────────────────────
prod            dark-mode           true      100
prod            new-checkout        false     0
dev             new-checkout        true      100
```

**DevOps uses Table for:** deployment event history, feature flags, VM inventory, simple config that does not need a full database.

---

### Queue Storage
A **message queue** for asynchronous communication between services. One service puts a message in, another service picks it up and processes it.

```
CI/CD pipeline finishes build
        │
        │ puts message into deployment-jobs queue:
        │ { "environment": "prod", "version": "v2.3", "image": "myapp:v2.3" }
        │
        ▼
   Queue: deployment-jobs
        │
        ▼
   Deployment service reads message → runs Terraform/kubectl/etc
        │
        ▼
   Deployment done → puts message in notifications queue:
   { "status": "success", "env": "prod", "version": "v2.3" }
        │
        ▼
   Notification service reads message → sends Slack/email alert
```

**DevOps uses Queue for:** decoupling services so they don't call each other directly, async job processing, retry handling (failed messages reappear after timeout).

---

## Why Private Endpoints on Specific Services?

```
Public access (default):
  Anyone with the right key/SAS can reach your storage from anywhere on internet.
  Acceptable for: general artifacts, logs.

Private endpoint (🔒):
  Storage service gets a private IP inside your VNet.
  Only VMs/services inside that VNet can reach it.
  Internet cannot reach it — even with valid credentials.

                              terraform.tfstate
We lock down:                 ── contains every resource ID, IPs, passwords ──
                              If leaked → attacker knows your entire infrastructure.

                              sensitive-data file share
                              ── contains: SSL certs, HR files, API keys ──
                              Must never be accessible from public internet.
```

**Rule:** Anything that contains credentials, secrets, or infrastructure details → Private Endpoint.

---

## Project Details

| Item | Details |
|------|---------|
| **Platform** | Azure only |
| **Difficulty** | Intermediate |
| **Estimated Time** | 3–4 hours (portal) |
| **Region** | East US |
| **Storage Account** | Standard ZRS (zone redundant — survives AZ failure) |
| **Blob Containers** | 5 (build-artifacts, app-logs, db-backups, terraform-state, temp) |
| **File Shares** | 2 (devops-configs SMB, sensitive-data SMB) |
| **Tables** | 2 (DeploymentLogs, FeatureFlags) |
| **Queues** | 2 (deployment-jobs, notifications) |
| **Lifecycle Policy** | 4 rules covering all blob containers |
| **Private Endpoints** | 2 (blob service + file service) |
| **IaC** | `Azure/bicep/main.bicep` |

---

## Requirements

- [ ] Azure account and subscription
- [ ] Logged into [portal.azure.com](https://portal.azure.com)
- [ ] Resource Group: `company-storage-rg` in East US
- [ ] Virtual Network: `company-vnet` with two subnets:
  - `app-subnet` 10.0.1.0/24
  - `pep-subnet` 10.0.2.0/24 ← for private endpoints

---

## Step-by-Step — Azure Portal

---

### PART 1: Create the Foundation

#### Step 1: Create Resource Group
1. Search **Resource Groups** → **Create**
2. Name: `company-storage-rg`, Region: East US
3. Create

#### Step 2: Create the VNet (needed before private endpoints)
1. Search **Virtual Networks** → **Create**
2. Name: `company-vnet`, Region: East US
3. IPv4: `10.0.0.0/16`
4. Add subnets:
   - `app-subnet` → `10.0.1.0/24`
   - `pep-subnet`  → `10.0.2.0/24`
5. Review + Create

#### Step 3: Create the Storage Account
1. Search **Storage Accounts** → **Create**
2. **Basics tab:**
   - Resource Group: `company-storage-rg`
   - Name: `companystorage<yourname>` (e.g. `companystorageveera`) — globally unique, lowercase only
   - Region: East US
   - Performance: **Standard**
   - Redundancy: **ZRS** ← Zone Redundant (survives if one Azure data center goes down)
3. **Advanced tab:**
   - Minimum TLS version: **TLS 1.2**
   - Allow blob public access: **Disabled** ← important
   - Enable blob versioning: **Enabled**
   - Enable blob soft delete: **Enabled**, Retention: **30 days**
   - Enable container soft delete: **Enabled**, Retention: **30 days**
   - Enable file share soft delete: **Enabled**, Retention: **30 days**
4. **Networking tab:**
   - Connectivity: **Disable public access and use private access** ← most secure
   
   > We will add private endpoints in Part 4. Selecting this now means the storage is invisible from internet. Only private endpoint connections will work.

5. Review + Create

---

### PART 2: Create Blob Containers

1. Go to your storage account → left menu → **Containers**
2. Click **+ Container** for each one below:

| Container Name | Access Level | Purpose |
|---------------|-------------|---------|
| `build-artifacts` | Private | CI/CD pipeline build outputs, deployment packages |
| `app-logs` | Private | Application logs rotated from VMs |
| `db-backups` | Private | Daily database backup files |
| `terraform-state` | Private | Terraform remote state files (most sensitive blob) |
| `temp` | Private | Temporary CI/CD workspace files, deleted in 3 days |

> All containers = **Private**. No exceptions. Access is controlled by IAM roles and SAS tokens.

After creating each container, click into it and add a note in the **Metadata** section:
- Key: `purpose`, Value: the description above (optional but good practice)

---

### PART 3: Create Azure File Shares

1. In your storage account → left menu → **File Shares**
2. Click **+ File Share** for each:

**Share 1: devops-configs**
- Name: `devops-configs`
- Tier: **Transaction optimized** (Standard)
- Protocol: **SMB**
- Quota: **10 GiB**
- Create

> This share is for shared config files across VMs. Less sensitive — only accessible from VNet via network rules.

**Share 2: sensitive-data**
- Name: `sensitive-data`
- Tier: **Transaction optimized**
- Protocol: **SMB**
- Quota: **5 GiB**
- Create

> This share is for SSL certificates, HR files, API key backups. Will get a Private Endpoint in Part 4.

---

### PART 4: Create Tables

1. In your storage account → left menu → **Tables**
2. Click **+ Table** for each:

| Table Name | Purpose |
|-----------|---------|
| `DeploymentLogs` | Record every deployment: who, when, env, status, duration |
| `FeatureFlags` | On/off switches per environment — read by apps at startup |

**Add test data to DeploymentLogs (portal):**
1. Click on `DeploymentLogs` table → **Edit** button at top → **Add Entity**
2. Add these properties:
   - PartitionKey: `prod`
   - RowKey: `2026-06-24T10-00-00`
   - Status: `Success`
   - DeployedBy: `github-actions`
   - Version: `v2.3.0`
   - DurationSeconds: `272`
3. Insert

**Add test data to FeatureFlags:**
1. Click `FeatureFlags` → **Add Entity**
   - PartitionKey: `prod`
   - RowKey: `dark-mode`
   - Enabled: `true` (type: Boolean)
   - RolloutPercent: `100` (type: Int32)
2. Add another:
   - PartitionKey: `prod`
   - RowKey: `new-checkout-flow`
   - Enabled: `false`
   - RolloutPercent: `0`

---

### PART 5: Create Queues

1. In your storage account → left menu → **Queues**
2. Click **+ Queue** for each:

| Queue Name | Purpose |
|-----------|---------|
| `deployment-jobs` | CI/CD pipeline puts a message here to trigger a deployment |
| `notifications` | Deployment service puts a message here after finishing — alerts/Slack |

**Test the Queue (add and read a message):**
1. Click on `deployment-jobs`
2. Click **Add message**
3. Message text:
   ```json
   {"environment":"prod","version":"v2.3","image":"myapp:v2.3","requestedBy":"github-actions"}
   ```
4. Expiry: 1 hour, Encode: No
5. Click **OK** — message appears in the queue
6. Click **Dequeue** to simulate a consumer reading the message
   - Message disappears from queue (processed)

> A queue message that fails processing reappears after the **visibility timeout** (default 30s). This is the built-in retry mechanism — no code needed.

---

### PART 6: Configure Lifecycle Management

1. In your storage account → left menu → **Data management > Lifecycle management**
2. Click **Add a rule** for each rule below:

---

**Rule 1: build-artifacts-tiering**
- Rule name: `build-artifacts-tiering`
- Rule scope: **Limit blobs with filters**
- Blob type: Block blobs

*Base blobs tab:*
| Condition | Days | Action |
|-----------|------|--------|
| Modified more than | 30 days | Tier to Cool |
| Modified more than | 90 days | Tier to Archive |
| Modified more than | 365 days | Delete |

*Filters tab:*
- Prefix: `build-artifacts/`

---

**Rule 2: app-logs-tiering**
- Rule name: `app-logs-tiering`

*Base blobs:*
| Days | Action |
|------|--------|
| 7 | Tier to Cool |
| 30 | Tier to Archive |
| 90 | Delete |

*Filters:* Prefix: `app-logs/`

---

**Rule 3: db-backups-tiering**
- Rule name: `db-backups-tiering`

*Base blobs:*
| Days | Action |
|------|--------|
| 30 | Tier to Cool |
| 90 | Tier to Archive |

> **No delete rule for db-backups** — compliance requires keeping database backups permanently.

*Filters:* Prefix: `db-backups/`

---

**Rule 4: temp-cleanup**
- Rule name: `temp-cleanup`

*Base blobs:*
| Days | Action |
|------|--------|
| 3 | Delete |

*Filters:* Prefix: `temp/`

---

**Rule 5: cleanup-old-versions**
- Rule name: `cleanup-old-versions`
- Blob subtype: **Previous versions** (not Base blobs)

*Version actions:*
| Days after version created | Action |
|---------------------------|--------|
| 30 | Delete |

*Filters:* No prefix — applies to all containers.

> Without this rule, versioning keeps every file change forever and storage costs grow without limit.

---

### PART 7: Create Private Endpoints

Private endpoints give the blob service and file service a **private IP inside your VNet**. Internet cannot reach them even if someone has credentials.

#### Private Endpoint 1: Blob Service (for terraform-state and db-backups)

1. In your storage account → left menu → **Networking > Private endpoint connections**
2. Click **+ Private endpoint**
3. **Basics tab:**
   - Resource Group: `company-storage-rg`
   - Name: `companystorage-blob-pep`
   - Region: East US
4. **Resource tab:**
   - Target sub-resource: **blob**
5. **Virtual Network tab:**
   - VNet: `company-vnet`
   - Subnet: `pep-subnet` ← private endpoints live in this dedicated subnet
6. **DNS tab:**
   - Integrate with private DNS zone: **Yes**
   - Azure creates `privatelink.blob.core.windows.net` zone automatically
7. Review + Create

> After creation, the blob service gets a private IP like `10.0.2.4` in your VNet.
> VMs in `app-subnet` reach blob storage via this private IP — traffic never leaves Azure network.

#### Private Endpoint 2: File Service (for sensitive-data share)

1. Same steps → **+ Private endpoint**
2. Name: `companystorage-file-pep`
3. Target sub-resource: **file**
4. Same VNet and `pep-subnet`
5. DNS zone: `privatelink.file.core.windows.net`
6. Review + Create

---

### PART 8: Verify Private Endpoints Work

After creating both private endpoints:

1. Go to **Networking > Private endpoint connections** in your storage account
2. You should see both endpoints with status **Approved**
3. Click on each endpoint → **DNS configuration** tab → you will see the private IP assigned (e.g. `10.0.2.4`, `10.0.2.5`)

**From a VM in app-subnet, verify name resolves to private IP:**
```bash
# SSH into a VM in app-subnet and test DNS resolution
nslookup companystorageveera.blob.core.windows.net
# Should resolve to 10.0.2.x (private IP), NOT a public Azure IP

nslookup companystorageveera.file.core.windows.net
# Should resolve to 10.0.2.x (private IP)
```

---

## How All Services Connect in a Real Company

```
Developer pushes code
    │
    ▼
CI/CD Pipeline (GitHub Actions / Azure DevOps)
    │
    ├── builds myapp-v2.3.zip
    │   └── uploads to  → blob: build-artifacts/releases/myapp-v2.3.zip
    │
    ├── puts message in queue → deployment-jobs: {"env":"prod","version":"v2.3"}
    │
    └── writes event to table → DeploymentLogs: {env:prod, version:v2.3, status:running}

Deployment Service (listens to deployment-jobs queue)
    │
    ├── reads message from queue → deployment-jobs
    │
    ├── downloads artifact ← blob: build-artifacts/releases/myapp-v2.3.zip
    │
    ├── reads config ← Azure Files: /mnt/devops-configs/app-settings.json
    │
    ├── reads Terraform state ← blob: terraform-state/networking/prod.tfstate
    │
    ├── reads SSL cert ← Azure Files (sensitive-data): /mnt/sensitive/app.crt
    │
    ├── runs deployment...
    │
    ├── updates DeploymentLogs table → status: Success, duration: 4m32s
    │
    └── puts message in queue → notifications: {"status":"success","env":"prod"}

Notification Service
    └── reads from notifications queue → sends Slack message to team
```

---

## Verification Checklist

### Blob Storage
- [ ] 5 containers created, all Private access
- [ ] File uploaded to `build-artifacts/releases/` folder
- [ ] File uploaded to `terraform-state/` — verify it shows as Hot tier
- [ ] Versioning tested: upload same file twice → Versions tab shows both versions
- [ ] Soft delete tested: delete a file → Show deleted blobs → Undelete

### Azure Files
- [ ] `devops-configs` share created (SMB, 10 GiB)
- [ ] `sensitive-data` share created (SMB, 5 GiB)
- [ ] File uploaded to each share from portal

### Table Storage
- [ ] `DeploymentLogs` table created with 1 test row
- [ ] `FeatureFlags` table created with 2 test rows (dark-mode, new-checkout-flow)
- [ ] Queried both tables in portal and see the data

### Queue Storage
- [ ] `deployment-jobs` queue created
- [ ] `notifications` queue created
- [ ] Added test message → saw it in queue → Dequeued it

### Lifecycle Management
- [ ] 5 rules created and visible in Code view as JSON
- [ ] Verified correct prefix filters on each rule
- [ ] version cleanup rule set to 30 days

### Private Endpoints
- [ ] Blob private endpoint created → status: Approved
- [ ] File private endpoint created → status: Approved
- [ ] Both show private IPs in DNS configuration (10.0.2.x)
