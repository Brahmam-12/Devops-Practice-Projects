# Project 3: Hub-Spoke VPC / VNet Peering

## Project Description

This project builds a **hub-spoke network topology** — the most common enterprise networking pattern in cloud. Real companies never put all their workloads in one VPC. They separate environments (dev, prod, staging) into different VPCs and connect them carefully.

You will create **3 VPCs / VNets** and connect them using VPC Peering (AWS) and VNet Peering (Azure). A central Hub holds shared services, and two Spokes hold separate environments.

### Why companies use Hub-Spoke

```
PROBLEM — everything in one VPC:              SOLUTION — hub-spoke:
────────────────────────────────────          ─────────────────────────────────────
One dev team's mistake can affect prod.       Dev VPC is completely isolated from Prod VPC.
All teams share the same network.             Teams have their own network boundaries.
One security breach = full access.            A breach in Spoke-A cannot reach Spoke-B.
Hard to apply different policies per env.     Each spoke has its own NSG / SG rules.
```

### How the 3 VPCs are connected

```
                    ┌─────────────────────────┐
                    │       Hub VPC            │
                    │     10.0.0.0/16          │
                    │  Shared Services:        │
                    │  - Bastion Host          │
                    │  - DNS / NTP servers     │
                    │  - Monitoring / Logging  │
                    └────────┬────────┬────────┘
                             │        │
               VPC Peering   │        │  VPC Peering
               hub↔spoke-a   │        │  hub↔spoke-b
                    ┌────────┘        └────────┐
                    ↓                          ↓
        ┌──────────────────┐      ┌──────────────────┐
        │   Spoke-A VPC     │      │   Spoke-B VPC     │
        │   10.1.0.0/16     │      │   10.2.0.0/16     │
        │   Dev Environment │      │   Prod Environment│
        └──────────────────┘      └──────────────────┘
              ❌ NOT connected to Spoke-B directly
```

### The most important concept — Non-Transitive Routing

This is the key learning in this project:

```
Hub can talk to Spoke-A  ✅   (peered)
Hub can talk to Spoke-B  ✅   (peered)
Spoke-A can talk to Hub  ✅   (peered)
Spoke-B can talk to Hub  ✅   (peered)

Spoke-A → Spoke-B?       ❌   BLOCKED

Even though Hub is between them, a packet from Spoke-A
CANNOT pass THROUGH Hub to reach Spoke-B.
VPC Peering is point-to-point, NOT a router.
```

This is called **non-transitive routing** — a peering connection only works between the two VPCs directly connected. To allow spoke-to-spoke traffic you need a different service (AWS Transit Gateway / Azure Virtual WAN).

### AWS vs Azure — Key Difference in Setup

```
AWS VPC Peering:                           Azure VNet Peering:
─────────────────────────────────          ─────────────────────────────────
Step 1: Create peering (requester side)    Step 1: Create peering in Hub VNet
Step 2: Accept peering (accepter side)       → this creates BOTH sides at once
Step 3: Add route in Hub route table       Step 2: Done — Azure auto-propagates
Step 4: Add route in Spoke route table       routes to both VNets automatically.
  → 4 manual steps, routes not automatic   → Much simpler than AWS
```

---

## Project Details

| Item                   | Details                                              |
|------------------------|------------------------------------------------------|
| **Project Name**       | Hub-Spoke VPC / VNet Peering                         |
| **Cloud Platforms**    | AWS + Azure (parallel implementation)                |
| **Difficulty**         | Intermediate                                         |
| **Estimated Time**     | 1.5–2 hours (console) / 15 min (Terraform/Bicep)    |
| **AWS Region**         | us-east-1                                            |
| **Azure Region**       | East US                                              |
| **VPCs / VNets**       | 3 total: Hub + Spoke-A + Spoke-B                     |
| **Hub CIDR**           | 10.0.0.0/16 (shared services)                        |
| **Spoke-A CIDR**       | 10.1.0.0/16 (dev environment)                        |
| **Spoke-B CIDR**       | 10.2.0.0/16 (prod environment)                       |
| **Peering connections**| 2: Hub↔Spoke-A and Hub↔Spoke-B                       |
| **IaC Files**          | `AWS/terraform/` and `Azure/bicep/`                  |
| **Diagrams**           | `Drawings/aws-hub-spoke.tldr` and `azure-hub-spoke.tldr` |

> **Important:** All 3 VPCs must use non-overlapping CIDRs. Peering fails if two VPCs share any IP range.

---

## Requirements

### Before You Start

**AWS Prerequisites:**
- [ ] AWS account with IAM permissions (VPC, EC2)
- [ ] AWS CLI installed and configured
- [ ] Terraform v1.5+ (for IaC deployment)
- [ ] An EC2 Key Pair in us-east-1

**Azure Prerequisites:**
- [ ] Azure account with Subscription
- [ ] Azure CLI installed (`az login`)
- [ ] Bicep CLI installed (`az bicep install`)
- [ ] Resource Group: `hub-spoke-rg` in East US

**Knowledge Prerequisites:**
- [ ] What a VPC, subnet, and route table is (Project 1)
- [ ] How Security Groups control traffic
- [ ] Basic understanding of IP routing / CIDR notation

---

## What You Will Build

| Component            | AWS Resource                   | Azure Resource                  | Purpose                                            |
|----------------------|--------------------------------|---------------------------------|----------------------------------------------------|
| Hub VPC/VNet         | aws_vpc (10.0.0.0/16)          | hub-vnet (10.0.0.0/16)          | Central network for shared services                |
| Spoke-A VPC/VNet     | aws_vpc (10.1.0.0/16)          | spoke-a-vnet (10.1.0.0/16)      | Dev environment — isolated                         |
| Spoke-B VPC/VNet     | aws_vpc (10.2.0.0/16)          | spoke-b-vnet (10.2.0.0/16)      | Prod environment — isolated                        |
| Peering Hub↔Spoke-A  | aws_vpc_peering_connection     | VNet Peering (both sides)       | Enables Hub ↔ Spoke-A communication                |
| Peering Hub↔Spoke-B  | aws_vpc_peering_connection     | VNet Peering (both sides)       | Enables Hub ↔ Spoke-B communication                |
| Hub Route Table      | Routes to 10.1/16 and 10.2/16  | Auto in Azure                   | Hub can send traffic to both spokes                |
| Spoke-A Route Table  | Route to 10.0/16               | Auto in Azure                   | Spoke-A can send traffic to Hub only               |
| Spoke-B Route Table  | Route to 10.0/16               | Auto in Azure                   | Spoke-B can send traffic to Hub only               |
| Bastion Host         | EC2 in Hub public subnet       | Azure Bastion in Hub VNet       | SSH jump server to access all VMs via Hub          |
| Test VMs             | 1 EC2 per VPC (3 total)        | 1 VM per VNet (3 total)         | Used to test ping / connectivity between VPCs      |
| Security Groups      | Hub-sg, Spoke-A-sg, Spoke-B-sg | NSGs per subnet                 | Allow ICMP + SSH only from peered CIDR ranges      |

---

## Learning Objectives

By completing this project you will be able to:

1. Explain what VPC Peering is and why CIDRs must not overlap
2. Create a VPC Peering connection in AWS and accept it from the other side
3. Manually add peering routes in AWS route tables (this is required — not automatic)
4. Create VNet Peering in Azure with automatic route propagation
5. Demonstrate non-transitive routing — prove Spoke-A cannot reach Spoke-B
6. Design a hub-spoke topology for real enterprise scenarios
7. Explain when you would upgrade from VPC Peering to Transit Gateway (AWS) or Virtual WAN (Azure)

---

## Architecture Overview

```
                ┌─────────────────────────┐
                │  Hub VPC 10.0.0.0/16    │
                │  (Shared Services)       │
                │  [DNS] [Monitoring]      │
                │  [Bastion] [Logging]     │
                └───────────┬─────────────┘
                            │
              VPC Peering   │   VPC Peering
              (Hub↔SpokeA)  │   (Hub↔SpokeB)
                    /────────┴────────\
                   /                   \
    ┌──────────────────┐   ┌──────────────────┐
    │  Spoke-A VPC      │   │  Spoke-B VPC      │
    │  10.1.0.0/16      │   │  10.2.0.0/16      │
    │  (Dev Env)        │   │  (Prod Env)        │
    │  10.1.1.0/24      │   │  10.2.1.0/24      │
    │  [Dev VMs]        │   │  [Prod VMs]        │
    └──────────────────┘   └──────────────────┘

Note: Spoke-A and Spoke-B are NOT peered to each other.
      Traffic between spokes must route through the Hub.
      (AWS VPC peering is non-transitive)
```

**Concepts covered:** VPC Peering, VNet Peering, Route Tables, Non-transitive routing, Hub-Spoke topology, Cross-VPC connectivity

---

## AWS Console — Step-by-Step

### Step 1: Create Three VPCs
Create each VPC individually:

| VPC Name       | CIDR          | Purpose        |
|----------------|---------------|----------------|
| hub-vpc        | 10.0.0.0/16   | Shared services|
| spoke-a-vpc    | 10.1.0.0/16   | Dev environment|
| spoke-b-vpc    | 10.2.0.0/16   | Prod environment|

For each:
1. **VPC > Create VPC**
2. Set name and CIDR as above
3. Enable DNS hostnames and DNS resolution

### Step 2: Create Subnets in Each VPC

**Hub VPC subnets:**
- `hub-private-1a`: `10.0.1.0/24` (us-east-1a)
- `hub-private-1b`: `10.0.2.0/24` (us-east-1b)
- `hub-public-1a`: `10.0.10.0/24` (for Bastion)

**Spoke-A subnets:**
- `spoke-a-subnet-1a`: `10.1.1.0/24`
- `spoke-a-subnet-1b`: `10.1.2.0/24`

**Spoke-B subnets:**
- `spoke-b-subnet-1a`: `10.2.1.0/24`
- `spoke-b-subnet-1b`: `10.2.2.0/24`

### Step 3: Create Internet Gateway for Hub VPC (Bastion needs this)

> **Only Hub VPC needs an IGW.** Spoke VPCs have no public-facing resources — all their VMs
> are private and reached through the bastion via peering. No IGW needed for spokes.

```
Without IGW:                          With IGW + Route Table:
─────────────────────────────────     ──────────────────────────────────
Internet → bastion public IP → ❌     Internet → IGW → hub-public-1a
Packet arrives at IGW but no              → bastion (public IP) ✅
route exists, traffic dropped.
```

**Create and attach IGW:**
1. **VPC > Internet Gateways > Create Internet Gateway**
2. Name: `hub-igw`
3. After creation → **Actions > Attach to VPC** → select `hub-vpc`

**Create public route table for hub-public-1a:**
1. **VPC > Route Tables > Create Route Table**
2. Name: `hub-public-rt`, VPC: `hub-vpc`
3. Select it → **Routes > Edit routes > Add route**
   - Destination: `0.0.0.0/0`
   - Target: **Internet Gateway** → `hub-igw`
4. **Subnet Associations > Edit > Associate** `hub-public-1a` only

> `hub-private-1a` and `hub-private-1b` must **NOT** be associated with this route table.
> Private subnets stay on the default route table (no IGW route) — that keeps them unreachable from internet.

**After this, the path works:**
```
Your Laptop → Internet → hub-igw → hub-public-1a → bastion (public IP)
```

---

### Step 4: Create VPC Peering Connections
1. **VPC > Peering Connections > Create Peering Connection**

**Peering 1: Hub ↔ Spoke-A**
- Name: `hub-to-spoke-a`
- Requester VPC: `hub-vpc`
- Accepter VPC: `spoke-a-vpc`
- Click **Create Peering Connection**
- Select it → **Actions > Accept Request**

**Peering 2: Hub ↔ Spoke-B**
- Name: `hub-to-spoke-b`
- Requester VPC: `hub-vpc`
- Accepter VPC: `spoke-b-vpc`
- Accept the request

> Do NOT create Spoke-A ↔ Spoke-B peering — this is the hub-spoke constraint.

### Step 5: Update Route Tables (CRITICAL STEP)

You must add routes in **both directions** for each peering.

**Hub VPC Route Table** → add routes to both spokes:
| Destination  | Target                    |
|--------------|---------------------------|
| 10.1.0.0/16  | pcx-hub-to-spoke-a (peer) |
| 10.2.0.0/16  | pcx-hub-to-spoke-b (peer) |

**Spoke-A Route Table** → add route back to hub:
| Destination  | Target                    |
|--------------|---------------------------|
| 10.0.0.0/16  | pcx-hub-to-spoke-a (peer) |

**Spoke-B Route Table** → add route back to hub:
| Destination  | Target                    |
|--------------|---------------------------|
| 10.0.0.0/16  | pcx-hub-to-spoke-b (peer) |

To edit routes:
1. **VPC > Route Tables** → select the table
2. **Routes > Edit routes > Add route**
3. Select **Peering Connection** as target
4. Save

### Step 6: Create Security Groups

> **Why SGs are required even with peering:**
> VPC Peering only adds a **route** between VPCs — it does not open any ports.
> The Security Group on each EC2 still blocks all traffic unless you explicitly allow it.
>
> **Why you use CIDR as source (not SG name):**
> In Project 1 you used `Source: alb-sg` (another SG). That only works inside the **same VPC**.
> For cross-VPC traffic you must use the **CIDR block** of the remote VPC as the source,
> because AWS cannot reference an SG from a different VPC.

Create one SG per VPC. Go to **EC2 > Security Groups > Create Security Group**, select the correct VPC for each.

---

**Hub SG** (`hub-sg`) — attach to `hub-vpc`

| Rule     | Protocol | Port | Source        | Purpose                                       |
|----------|----------|------|---------------|-----------------------------------------------|
| Inbound  | TCP      | 22   | Your IP `/32` | SSH from your laptop → bastion                |
| Outbound | All      | All  | `0.0.0.0/0`  | Bastion initiates SSH outbound to all VMs     |

> **Why only 1 inbound rule on hub-sg?**
> The bastion is a **management jump server** — it always initiates connections, it never receives
> them from spoke VMs. Spoke-A VM has zero reason to connect back to the bastion.
> Because SGs are stateful, return packets from spoke VMs back to the bastion (after bastion
> initiated the SSH) are automatically allowed — no inbound rule needed for that.

---

**Spoke-A SG** (`spoke-a-sg`) — attach to `spoke-a-vpc`

| Rule      | Protocol | Port | Source          | Purpose                                |
|-----------|----------|------|-----------------|----------------------------------------|
| Inbound   | TCP      | 22   | `10.0.0.0/16`   | SSH from Hub (bastion → spoke-a-vm)    |
| Inbound   | ICMP     | All  | `10.0.0.0/16`   | Allow ping from Hub                    |
| Outbound  | All      | All  | `0.0.0.0/0`     | Allow all outbound                     |

---

**Spoke-B SG** (`spoke-b-sg`) — attach to `spoke-b-vpc`

| Rule      | Protocol | Port | Source          | Purpose                                |
|-----------|----------|------|-----------------|----------------------------------------|
| Inbound   | TCP      | 22   | `10.0.0.0/16`   | SSH from Hub (bastion → spoke-b-vm)    |
| Inbound   | ICMP     | All  | `10.0.0.0/16`   | Allow ping from Hub                    |
| Outbound  | All      | All  | `0.0.0.0/0`     | Allow all outbound                     |

> **Note:** Spoke-A SG does NOT allow traffic from `10.2.0.0/16` (Spoke-B) and vice versa.
> This reinforces the isolation — even if routing existed, the SG would block it.

### Step 7: Launch Bastion Host in Hub VPC

> The bastion is your **only entry point** into all 3 VPCs. It lives in the Hub public subnet and
> can reach Spoke VMs through the peering connections you created.

1. **EC2 > Launch Instance**
2. Name: `hub-bastion`
3. AMI: Amazon Linux 2023, Type: `t3.micro`
4. **Network**: `hub-vpc`, **Subnet**: `hub-public-1a` ← must be PUBLIC subnet
5. **Auto-assign Public IP**: Enable ← this gives it a reachable IP
6. **Security Group**: `hub-sg` (allow SSH port 22 from your IP)
7. **Key pair**: select your key pair
8. Launch

> `hub-bastion` has a **public IP** — this is the ONLY instance in this project you SSH to directly.

---

### Step 8: Launch Test EC2 Instances (Private — no public IP)

Launch one EC2 in each VPC's **private** subnet for connectivity testing:

| Instance Name  | VPC      | Subnet              | Security Group | Public IP |
|----------------|----------|---------------------|----------------|-----------|
| `hub-test-vm`  | hub-vpc  | `hub-private-1a`    | `hub-sg`       | None      |
| `spoke-a-vm`   | spoke-a  | `spoke-a-subnet-1a` | `spoke-a-sg`   | None      |
| `spoke-b-vm`   | spoke-b  | `spoke-b-subnet-1a` | `spoke-b-sg`   | None      |

For each: AMI Amazon Linux 2023, t3.micro, **Auto-assign Public IP: Disable**.

> These 3 instances have **no public IP** — you cannot SSH to them directly from your laptop.
> You must go through the bastion first.

---

### Step 9: How to Connect — SSH Chain

```
Your Laptop
    │
    │  ssh to public IP
    ▼
hub-bastion  (public subnet, has public IP)
    │
    │  from here, ssh to private IPs using peering routes
    ├──► hub-test-vm   (10.0.1.x  — same VPC)
    ├──► spoke-a-vm    (10.1.1.x  — reachable via hub↔spoke-a peering)
    └──► spoke-b-vm    (10.2.1.x  — reachable via hub↔spoke-b peering)
```

**Option A — SSH Agent Forwarding (recommended)**

This forwards your laptop's key to the bastion so you can SSH onward without copying the key file.

```bash
# Step 1: Add your key to SSH agent on your laptop
ssh-add key.pem

# Step 2: SSH to bastion WITH agent forwarding (-A flag)
ssh -A -i key.pem ec2-user@<hub-bastion-public-ip>

# Step 3: From bastion, SSH to hub-test-vm (private IP — no -i needed, agent handles it)
ssh ec2-user@10.0.1.x

# Step 4: From bastion, SSH to spoke-a-vm
ssh ec2-user@10.1.1.x

# Step 5: From bastion, SSH to spoke-b-vm
ssh ec2-user@10.2.1.x
```

**Option B — Jump Host flag (single command from laptop)**

```bash
# SSH directly to spoke-a-vm through bastion in one command
ssh -i key.pem -J ec2-user@<hub-bastion-public-ip> ec2-user@10.1.1.x
#                  ─── jump via bastion ───────────  ─── final destination ───
```

### Step 10: Test Connectivity
```bash
# SSH to bastion first
ssh -A -i key.pem ec2-user@<hub-bastion-public-ip>

# From bastion, ping hub-test-vm (same VPC — always works)
ping 10.0.1.x   # ✅ Should succeed

# From bastion, ping spoke-a (peered)
ping 10.1.1.x   # ✅ Should succeed

# From bastion, ping spoke-b (peered)
ping 10.2.1.x   # ✅ Should succeed

# Now SSH into spoke-a-vm FROM the bastion
ssh ec2-user@10.1.1.x      # you are now inside spoke-a-vm

# From spoke-a-vm, ping spoke-b (SHOULD FAIL — not peered directly)
ping 10.2.1.x   # ❌ Should fail (non-transitive routing)

# Verify with traceroute — packet gets dropped, does NOT route through hub
traceroute 10.2.1.x

# Exit back to bastion
exit
```

> **Why ping fails from Spoke-A to Spoke-B:**
> Even though Hub is between them, Hub does NOT act as a router for this traffic.
> VPC Peering is a direct point-to-point link — it does not forward packets to a third VPC.
> Spoke-A has no route to 10.2.0.0/16 in its route table, so the packet is dropped.

---

## Azure Portal — Step-by-Step (VNet Peering)

### Step 1: Create Three Virtual Networks
| VNet Name    | CIDR          | Region   |
|--------------|---------------|----------|
| hub-vnet     | 10.0.0.0/16   | East US  |
| spoke-a-vnet | 10.1.0.0/16   | East US  |
| spoke-b-vnet | 10.2.0.0/16   | East US  |

For each: **Virtual Networks > Create**, set CIDR and add subnets.

### Step 2: Create VNet Peerings
Azure peering is bidirectional in one step.

**Hub ↔ Spoke-A:**
1. Go to `hub-vnet` → **Peerings > Add**
2. Peering link name (this side): `hub-to-spoke-a`
3. Remote VNet: `spoke-a-vnet`
4. Peering link name (remote side): `spoke-a-to-hub`
5. Enable:
   - Allow `hub-vnet` to access `spoke-a-vnet`
   - Allow `spoke-a-vnet` to access `hub-vnet`
6. Click **Add**

**Hub ↔ Spoke-B** (same process):
1. Add peering from `hub-vnet` → `spoke-b-vnet`

> Unlike AWS, Azure peering creates routes automatically — no manual route table editing needed.

### Step 3: Verify Effective Routes
After peering, check that routes propagated:
1. Create a VM in each VNet
2. VM → **Networking > Effective Routes**
3. You should see routes to all peered VNet CIDRs

### Step 4: Test Connectivity
```bash
# From hub VM, ping spoke-a VM
ping 10.1.1.4  # Should work

# From hub VM, ping spoke-b VM
ping 10.2.1.4  # Should work

# From spoke-a VM, ping spoke-b VM
ping 10.2.1.4  # Should FAIL (no direct peering)
```

---

## Understanding Non-Transitive Routing

```
Spoke-A (10.1.x.x) ←→ Hub (10.0.x.x) ←→ Spoke-B (10.2.x.x)
         ✅ Peered              ✅ Peered

Spoke-A → Spoke-B?
  AWS:   ❌ Not transitive — packet dropped even if Hub could forward it
  Azure: ❌ Same — unless you use Azure Firewall / Route Server in Hub
```

**To enable spoke-to-spoke routing, you need:**
- AWS: Transit Gateway (separate service)
- Azure: Azure Virtual WAN or Azure Firewall in Hub + UDRs

---

## Key Concepts Reinforced

| Concept            | What You Practiced                                    |
|--------------------|-------------------------------------------------------|
| VPC Peering        | Manual two-way route configuration required           |
| VNet Peering       | Automatic route propagation, bidirectional setup      |
| Hub-Spoke          | Centralized shared services, isolation between spokes |
| Non-transitive     | Direct peering ≠ transitive routing                   |
| Route Tables       | Must explicitly add peering destinations              |
| Security Groups    | Allow CIDRs of peered VPCs as sources                |
