# Project 1: Multi-Tier Web App VPC / VNet

## Project Description

This project builds a **production-style web application network** on both AWS and Azure using a **2-tier compute + ALB-as-web-layer** pattern — the most common real-world AWS/Azure design.

### How the tiers work in this project

```
Tier          Where it runs               What it does
──────────────────────────────────────────────────────────────────
Web Layer     ALB (in public subnets)     Receives HTTP from internet,
                                          terminates SSL, routes to EC2.
                                          ALB gets auto DNS name from AWS.
                                          NO separate web EC2 needed here.

App Layer     EC2 / VM (private subnets)  Runs nginx + your application code.
                                          No public IP. Only ALB can reach it.
                                          Outbound internet via NAT Gateway.

DB Layer      RDS / Azure SQL (private)   Database. Only App EC2 can reach it
                                          (Security Group rule: port 3306 from
                                          app-sg only). Zero internet access.
```

### Why no web EC2 in the public subnet?

In cloud architecture, the **ALB takes the role of the web tier**:
- It receives all HTTP/HTTPS traffic from the internet
- It health-checks your app EC2 and load balances across AZs
- It gives you a DNS hostname (e.g. `alb-xxx.us-east-1.elb.amazonaws.com`) automatically

A separate nginx EC2 in the public subnet would just be a redundant proxy — the ALB already does that job.

> **True 3-tier** (used in large-scale apps): Internet → ALB → Web EC2 (nginx/static) → App EC2 (API/backend) → DB. That pattern makes sense when your web and app layers need to scale independently. This project uses the simpler and more common version.

### Why does ALB need subnets if it creates a DNS name automatically?

The ALB is **not just a DNS record** — AWS physically deploys load balancer nodes (called ENIs) inside YOUR VPC subnets, one per Availability Zone. The DNS name resolves to the IPs of those ENIs. You must specify which subnets so AWS knows:
1. Which AZs to place nodes in (you need at least 2 for HA)
2. That the nodes should be in **public** subnets (so they get public IPs and can receive internet traffic)

Without picking public subnets → ALB nodes get no public IP → internet can't reach them.

### Where does nginx / web software get installed?

On the **App EC2 instances** in the private subnets. The EC2 user-data script installs nginx automatically at launch. The flow is:

```
User browser → ALB DNS → ALB node (public subnet) → port 80 → App EC2 nginx (private subnet)
```

The Bastion Host in the public subnet is only for YOUR SSH admin access — it never serves web traffic.

---

## Project Details

| Item                  | Details                                      |
|-----------------------|----------------------------------------------|
| **Project Name**      | Multi-Tier Web App VPC                       |
| **Cloud Platforms**   | AWS + Azure (parallel implementation)        |
| **Difficulty**        | Beginner → Intermediate                      |
| **Estimated Time**    | 2–3 hours (console) / 15 min (Terraform/Bicep) |
| **AWS Region**        | us-east-1 (N. Virginia)                      |
| **Azure Region**      | East US                                      |
| **VPC / VNet CIDR**   | 10.0.0.0/16                                  |
| **Availability Zones**| 2 (1a and 1b)                                |
| **Total Subnets**     | 6 (2 public + 2 app private + 2 DB private)  |
| **IaC Files**         | `AWS/terraform/` and `Azure/bicep/`          |
| **Diagrams**          | `Drawings/aws-multi-tier.tldr` and `azure-multi-tier.tldr` |

---

## Requirements

### Before You Start

**AWS Prerequisites:**
- [ ] AWS account with IAM user (AdministratorAccess or custom VPC + EC2 policy)
- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] Terraform v1.5+ installed (for IaC deployment)
- [ ] An EC2 Key Pair created in us-east-1 (for SSH to Bastion)
- [ ] Your public IP address (for restricting Bastion SSH access)

**Azure Prerequisites:**
- [ ] Azure account with Subscription (Free tier works)
- [ ] Azure CLI installed and logged in (`az login`)
- [ ] Bicep CLI installed (`az bicep install`)
- [ ] A Resource Group created: `multi-tier-rg` in East US

**Knowledge Prerequisites:**
- [ ] What a VPC and subnet is (covered in your VPC notes)
- [ ] Basic understanding of TCP/IP and CIDR notation
- [ ] What Security Groups and NACLs do (covered in your NSG/ASG/NACL notes)

---

## What You Will Build

| Component           | AWS Resource               | Azure Resource           | What runs here / purpose                              |
|---------------------|----------------------------|--------------------------|-------------------------------------------------------|
| Network             | VPC (10.0.0.0/16)          | VNet (10.0.0.0/16)       | Isolated private network                              |
| **Web layer**       | **ALB** (in public subnet) | **Azure Standard LB**    | **Receives HTTP from internet. Acts as the web tier. Auto DNS name. NO web EC2 needed.** |
| Public Subnet ×2    | 10.0.1.0/24, 10.0.2.0/24  | 10.0.1.0/24, 10.0.2.0/24 | ALB nodes live here (1 per AZ). Also Bastion Host.   |
| **App Tier EC2**    | **EC2 + nginx** (private)  | **VM + nginx** (private) | **nginx + your app code runs here. Reached only by ALB.** |
| App Subnet ×2       | 10.0.3.0/24, 10.0.4.0/24  | 10.0.3.0/24, 10.0.4.0/24 | App EC2/VMs live here. No public IP. Internet via NAT. |
| **DB Tier**         | **RDS MySQL** (private)    | **Azure SQL** (private)  | **Database. Only App EC2 can connect (port 3306).**   |
| DB Subnet ×2        | 10.0.5.0/24, 10.0.6.0/24  | 10.0.5.0/24, 10.0.6.0/24 | RDS/DB VMs. No internet access at all.               |
| Internet Gateway    | aws_internet_gateway       | Automatic in Azure       | Allows public subnets to reach internet (inbound + outbound) |
| NAT Gateway + EIP   | aws_nat_gateway            | Azure NAT / LB outbound  | Allows private EC2 to reach internet outbound only   |
| Route Table (public)| Routes 0.0.0.0/0 → IGW    | Auto in Azure             | Sends internet traffic through IGW                   |
| Route Table (private)| Routes 0.0.0.0/0 → NAT   | Auto in Azure             | Sends outbound traffic through NAT (no inbound)      |
| Bastion Host        | EC2 in public subnet       | Azure Bastion service     | YOUR SSH jump box for admin access to private EC2    |
| SG: ALB             | alb-sg (port 80/443 open)  | NSG on public subnet     | Allows internet → ALB                                |
| SG: App EC2         | app-sg (port 80 from alb-sg only) | NSG on app subnet | ALB → EC2 only. No direct internet.                  |
| SG: DB              | db-sg (port 3306 from app-sg only) | NSG on db subnet | App EC2 → DB only. Blocks everything else.           |
| NACL on DB subnet   | Stateless subnet firewall  | NSG (same role)          | 2nd layer: blocks all except port 3306 from app CIDR |

---

## Learning Objectives

By completing this project you will be able to:

1. Design a multi-tier network with proper subnet segmentation
2. Explain why public subnets need an IGW and private subnets need a NAT Gateway
3. Configure Security Groups with least-privilege (tier-to-tier rules, not 0.0.0.0/0)
4. Add a NACL as a second layer of defense on the DB subnet
5. Set up an Application Load Balancer with a Target Group and health checks
6. SSH into a private EC2 instance using a Bastion Host as a jump server
7. Compare AWS and Azure equivalents for each component

---

## Architecture Overview

```
                        [ Internet ]
                             |
                    [ Internet Gateway ]
                             |
              [ Application Load Balancer ]
                      /            \
        ┌─────────────────────────────────────────────┐
        │  VPC: 10.0.0.0/16                           │
        │                                             │
        │  ┌─── AZ-1a ──────────┐  ┌─── AZ-1b ────┐  │
        │  │ Public 10.0.1.0/24 │  │ 10.0.2.0/24  │  │
        │  │  [Bastion] [NATGW] │  │  [Web EC2]   │  │
        │  │                    │  │              │  │
        │  │ App    10.0.3.0/24 │  │ 10.0.4.0/24  │  │
        │  │  [EC2 App Server]  │  │ [EC2 App]    │  │
        │  │                    │  │              │  │
        │  │ DB     10.0.5.0/24 │  │ 10.0.6.0/24  │  │
        │  │  [RDS MySQL]       │  │  [RDS]       │  │
        │  └────────────────────┘  └──────────────┘  │
        └─────────────────────────────────────────────┘
```

**Concepts covered:** VPC, Subnets, IGW, NAT Gateway, ALB, Route Tables, Security Groups, NACLs, Bastion Host, EC2

---

## AWS Console — Step-by-Step

### Step 1: Create the VPC
1. Go to **VPC > Your VPCs > Create VPC**
2. Select **VPC only**
3. Name: `multi-tier-vpc`
4. IPv4 CIDR: `10.0.0.0/16`
5. Click **Create VPC**

### Step 2: Create Subnets (6 total)
Go to **VPC > Subnets > Create Subnet**, select your VPC.

| Subnet Name              | AZ         | CIDR          | Type    |
|--------------------------|------------|---------------|---------|
| public-subnet-1a         | us-east-1a | 10.0.1.0/24   | Public  |
| public-subnet-1b         | us-east-1b | 10.0.2.0/24   | Public  |
| app-private-subnet-1a    | us-east-1a | 10.0.3.0/24   | Private |
| app-private-subnet-1b    | us-east-1b | 10.0.4.0/24   | Private |
| db-private-subnet-1a     | us-east-1a | 10.0.5.0/24   | Private |
| db-private-subnet-1b     | us-east-1b | 10.0.6.0/24   | Private |

For public subnets: select each → **Actions > Edit subnet settings** → enable **Auto-assign public IPv4**.

### Step 3: Create and Attach Internet Gateway
1. **VPC > Internet Gateways > Create Internet Gateway**
2. Name: `multi-tier-igw`
3. After creation: **Actions > Attach to VPC** → select `multi-tier-vpc`

### Step 4: Create NAT Gateway

> **Zone vs Regional — which to pick?**
>
> | Type | Subnet required | Covers | Best for |
> |------|----------------|--------|----------|
> | **Zone** (old default) | Yes — tied to one AZ | Only that AZ | Learning / single-AZ setups |
> | **Regional** *(new — recommended)* | No | All AZs in the region automatically | Multi-AZ production setups |
>
> **Use Regional** — one NAT Gateway covers all your AZs. If AZ-1a goes down, private EC2s in AZ-1b still have internet. No extra cost per AZ, no extra management.

**Using Regional NAT Gateway (recommended):**
1. **VPC > NAT Gateways > Create NAT Gateway**
2. Name: `multi-tier-nat-gw`
3. Connectivity: **Public**
4. NAT Gateway type: **Regional** ← select this
5. Click **Allocate Elastic IP**, then **Create NAT Gateway**
6. Wait for status to become **Available** (~2 min)
7. In your **private route table**: add route `0.0.0.0/0 → multi-tier-nat-gw` (same as before)

**If you chose Zone (AZ-specific) instead:**
- You must create one NAT GW per AZ for full HA:
  - `nat-gw-1a` in `public-subnet-1a` → associate with AZ-1a private route table
  - `nat-gw-1b` in `public-subnet-1b` → associate with AZ-1b private route table
- This costs more but teaches you how the zone model works

### Step 5: Create Route Tables
**Public Route Table:**
1. **VPC > Route Tables > Create Route Table**
2. Name: `public-rt`, VPC: `multi-tier-vpc`
3. Select it → **Routes > Edit routes > Add route**: `0.0.0.0/0` → target: **IGW** (`multi-tier-igw`)
4. **Subnet associations > Edit > Associate** both public subnets

**Private Route Table:**
1. Create route table: `private-rt`
2. Add route: `0.0.0.0/0` → target: **NAT Gateway** (`multi-tier-nat-gw`)
3. Associate all 4 private subnets (app + db)

### Step 6: Create Security Groups
**Bastion SG** (`bastion-sg`):
- Inbound: Port 22 / TCP / Your IP (`x.x.x.x/32`)
- Outbound: All traffic

**ALB SG** (`alb-sg`):
- Inbound: Port 80/443 / TCP / `0.0.0.0/0`
- Outbound: All traffic

**Web/App SG** (`app-sg`):
- Inbound: Port 80 / TCP / Source: `alb-sg`
- Inbound: Port 22 / TCP / Source: `bastion-sg`
- Outbound: All traffic

**DB SG** (`db-sg`):
- Inbound: Port 3306 / TCP / Source: `app-sg`
- Outbound: All traffic

### Step 7: Launch Bastion Host
1. **EC2 > Launch Instance**
2. Name: `bastion-host`
3. AMI: Amazon Linux 2023
4. Type: `t3.micro`
5. Network: `multi-tier-vpc`, Subnet: `public-subnet-1a`
6. Auto-assign Public IP: **Enable**
7. Security Group: `bastion-sg`
8. Key pair: select or create one

### Step 8: Launch App EC2 Instances
Repeat for 2 instances:
- Subnet: `app-private-subnet-1a` and `app-private-subnet-1b`
- Security Group: `app-sg`
- No public IP
- User data (add to install nginx):
```bash
#!/bin/bash
yum update -y
yum install -y nginx
systemctl start nginx
systemctl enable nginx
```

### Step 9: Create Application Load Balancer
1. **EC2 > Load Balancers > Create Load Balancer > Application**
2. Name: `multi-tier-alb`
3. Scheme: **Internet-facing**
4. VPC: `multi-tier-vpc`
5. Subnets: both **public** subnets
6. Security Group: `alb-sg`
7. Listener: HTTP port 80

### Step 10: Create Target Group
1. **EC2 > Target Groups > Create Target Group**
2. Type: **Instances**, Port: **80**, Protocol: HTTP
3. VPC: `multi-tier-vpc`
4. Health check path: `/`
5. Healthy threshold: 2 / Unhealthy threshold: 3 / Interval: 30s
6. **Next** → register both app EC2 instances → **Create**
7. Go back to ALB → Listeners → Edit HTTP:80 listener → forward to this target group

> **Why port 80?** Your app EC2 user-data installs nginx, which listens on port 80 by default.
> If you set port 8080 here, health checks will fail (nothing runs on 8080) and both instances show **Unhealthy**.
> ALB port (80) → Target Group port (80) → nginx on EC2 (80) — all three must match.

### Step 11: Create NACLs (Optional Layer)
1. **VPC > Network ACLs > Create Network ACL**
2. Associate with DB subnets
3. Add inbound rule: Port 3306, Source: `10.0.3.0/24` and `10.0.4.0/24` (app subnets only)
4. Deny all other inbound

---

## Azure Portal — Step-by-Step

### Step 1: Create Resource Group
1. **Resource Groups > Create**
2. Name: `multi-tier-rg`, Region: `East US`

### Step 2: Create Virtual Network
1. **Virtual Networks > Create**
2. Name: `multi-tier-vnet`, CIDR: `10.0.0.0/16`
3. Add subnets during creation:

| Subnet Name        | CIDR          | Purpose        |
|--------------------|---------------|----------------|
| public-subnet-1    | 10.0.1.0/24   | Web/Public     |
| public-subnet-2    | 10.0.2.0/24   | Web/Public     |
| app-subnet-1       | 10.0.3.0/24   | App tier       |
| app-subnet-2       | 10.0.4.0/24   | App tier       |
| db-subnet-1        | 10.0.5.0/24   | DB tier        |
| db-subnet-2        | 10.0.6.0/24   | DB tier        |
| AzureBastionSubnet | 10.0.100.0/27 | Azure Bastion (must be this name) |

### Step 3: Create Network Security Groups
Create NSGs for each tier. For each NSG:
1. **Network Security Groups > Create**
2. Assign to your resource group

**app-nsg** rules:
- Inbound: Port 80, Source: VNet CIDR `10.0.0.0/16`
- Inbound: Port 22, Source: `AzureBastionSubnet`

**db-nsg** rules:
- Inbound: Port 3306, Source: App subnet CIDR only
- Deny all other inbound (default)

Associate each NSG: **NSG > Subnets > Associate** → select the matching subnet.

### Step 4: Deploy Azure Bastion
1. **Bastions > Create**
2. Name: `multi-tier-bastion`
3. VNet: `multi-tier-vnet`
4. Subnet: `AzureBastionSubnet` (auto-selected)
5. Public IP: Create new

### Step 5: Create VMs
1. **Virtual Machines > Create**
2. For web/app VMs: select `app-subnet-1`, no public IP
3. Size: `Standard_B2s`
4. NSG: assign `app-nsg`
5. Repeat for second AZ using `app-subnet-2`

### Step 6: Create Azure Load Balancer
1. **Load Balancers > Create**
2. Name: `multi-tier-lb`, Tier: **Standard**
3. Type: **Public**, SKU: Standard
4. **Backend pools**: add both app VMs
5. **Health probe**: HTTP, port 80, path `/`
6. **Load balancing rule**: Port 80 → Backend port 80

---

## Testing & Verification

```bash
# 1. Test bastion SSH (AWS)
ssh -i key.pem ec2-user@<bastion-public-ip>

# 2. From bastion, test private instance
ssh -i key.pem ec2-user@10.0.3.x

# 3. Test NAT Gateway (from private instance)
curl https://checkip.amazonaws.com  # should return NAT GW IP

# 4. Test Load Balancer
curl http://<alb-dns-name>  # should return nginx welcome page

# 5. Verify security group isolation
# From app instance, try connecting to DB port
nc -zv 10.0.5.x 3306  # should succeed
nc -zv 10.0.5.x 22    # should fail (DB SG only allows 3306)
```

---

## Deploy with IaC

```bash
# Terraform (AWS)
cd AWS/terraform
terraform init
terraform plan -var="key_pair_name=your-key" -var="allowed_ssh_cidr=x.x.x.x/32"
terraform apply

# Bicep (Azure)
cd Azure/bicep
az group create --name multi-tier-rg --location eastus
az deployment group create \
  --resource-group multi-tier-rg \
  --template-file main.bicep
```

---

## Key Concepts Reinforced

| Concept          | What You Practiced                                      |
|------------------|---------------------------------------------------------|
| VPC / VNet       | Created with custom CIDR, DNS enabled                  |
| Subnets          | Public vs private, multi-AZ design                     |
| IGW              | Enables outbound and inbound internet for public subnet |
| NAT Gateway      | Outbound-only internet for private subnets              |
| Route Tables     | Separate tables for public (IGW) and private (NAT)     |
| Security Groups  | Least-privilege, tier-to-tier rules                    |
| NACLs            | Stateless, subnet-level firewall layer                 |
| ALB              | Layer 7 load balancer with target groups               |
| Bastion Host     | Secure jump server for private instance access         |
