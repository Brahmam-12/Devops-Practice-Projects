# Project 2: Highly Available App — ALB + Auto Scaling

## Project Description

This project builds a **self-healing, auto-scaling web application** where your infrastructure responds automatically to traffic and failures — no manual intervention needed.

In Project 1 you manually launched 2 app EC2 instances. The problem: if one crashes, it stays down until you fix it. If traffic doubles overnight, your app slows down. This project solves both problems.

### How the three pieces work together

```
Component         Role                               How it connects
────────────────────────────────────────────────────────────────────────
ALB               Entry point for all traffic        Sits in public subnets.
                  Distributes requests across         Checks each EC2 health
                  all healthy EC2 instances.          every 30 seconds.
                  If an EC2 is unhealthy →
                  ALB stops sending it traffic.

Target Group      The "list" that ALB uses           ALB forwards to Target Group.
                  to know which EC2 instances         EC2s register themselves here.
                  are available.                      Health check results stored here.

Auto Scaling      Manages the EC2 fleet.             Reads Target Group health.
Group (ASG)       Replaces terminated instances.     Adds EC2s when CPU is high.
                  Keeps min/desired/max count.       Removes EC2s when CPU is low.
                  Spreads instances across AZs.
```

### What "self-healing" means here

```
Scenario 1 — EC2 crashes:
  EC2 crashes → ALB health check fails → ALB stops routing to it
  → ASG detects instance is unhealthy → ASG terminates it
  → ASG launches a replacement EC2 in the same AZ
  Total time: ~3–5 minutes, zero manual work

Scenario 2 — Traffic spike (CPU > 70%):
  CPU rises above 70% for 5 minutes → CloudWatch alarm triggers
  → ASG scale-out policy fires → 2 new EC2s launched
  → New EC2s register with Target Group → ALB starts sending them traffic
  Total time: ~3–4 minutes

Scenario 3 — Traffic drops (CPU < 30%):
  CPU drops below 30% for 10 minutes → ASG scale-in fires
  → 1 EC2 removed (ASG always keeps minimum count)
  Total time: 10 min cooldown to avoid thrashing
```

### What the Launch Template does

Before ASG can launch an EC2, it needs a blueprint — that is the **Launch Template**:
- Which AMI (Amazon Linux 2023)
- Which instance type (t3.small)
- Which Security Group
- What user-data script runs at boot (installs nginx, writes the instance ID and AZ to the webpage)

Every EC2 that ASG launches is identical and comes up ready automatically.

---

## Project Details

| Item                   | Details                                          |
|------------------------|--------------------------------------------------|
| **Project Name**       | HA App — ALB + Auto Scaling Group                |
| **Cloud Platforms**    | AWS + Azure (parallel implementation)            |
| **Difficulty**         | Intermediate                                     |
| **Estimated Time**     | 2–3 hours (console) / 15 min (Terraform/Bicep)  |
| **AWS Region**         | us-east-1 (N. Virginia)                          |
| **Azure Region**       | East US                                          |
| **VPC CIDR**           | 10.0.0.0/16                                      |
| **Availability Zones** | 2 (1a and 1b)                                    |
| **Subnets**            | 4 total: 2 public (ALB) + 2 private (EC2)       |
| **ASG Config**         | min: 2, desired: 2, max: 6                       |
| **Scaling Trigger**    | CPU > 70% → scale out / CPU < 30% → scale in    |
| **Azure Equivalent**   | Virtual Machine Scale Set (VMSS) + Azure Monitor |
| **IaC Files**          | `AWS/terraform/` and `Azure/bicep/`              |
| **Diagrams**           | `Drawings/aws-ha-alb.tldr` and `azure-ha-lb.tldr`|

---

## Requirements

### Before You Start

**AWS Prerequisites:**
- [ ] AWS account with IAM user (EC2, VPC, AutoScaling, ELB permissions)
- [ ] AWS CLI installed and configured
- [ ] Terraform v1.5+ (for IaC deployment)
- [ ] An EC2 Key Pair in us-east-1
- [ ] Project 1 completed or basic VPC knowledge

**Azure Prerequisites:**
- [ ] Azure account with Subscription
- [ ] Azure CLI installed and logged in (`az login`)
- [ ] Bicep CLI installed (`az bicep install`)
- [ ] Resource Group: `ha-app-rg` in East US

**Knowledge Prerequisites:**
- [ ] What a Load Balancer does (Project 1 covered ALB basics)
- [ ] What EC2 and Security Groups are
- [ ] What a VPC, subnets, and route tables are (Project 1)

---

## What You Will Build

| Component           | AWS Resource                    | Azure Resource              | Purpose                                              |
|---------------------|---------------------------------|-----------------------------|------------------------------------------------------|
| Network             | VPC (10.0.0.0/16)               | VNet (10.0.0.0/16)          | Isolated network                                     |
| Public Subnets ×2   | 10.0.1.0/24, 10.0.2.0/24        | 10.0.1.0/24 (lb-subnet)    | ALB nodes live here (one per AZ)                    |
| Private Subnets ×2  | 10.0.3.0/24, 10.0.4.0/24        | 10.0.2.0/24 (app-subnet)   | EC2 / VMSS instances live here                       |
| Launch Template     | aws_launch_template             | VMSS image config           | Blueprint for every EC2 ASG launches                 |
| Application LB      | aws_lb (internet-facing)        | Azure Standard LB (Public)  | Entry point — distributes HTTP traffic               |
| Target Group        | aws_lb_target_group             | LB Backend Pool             | List of healthy EC2s ALB sends traffic to            |
| Health Check        | HTTP GET / every 30s            | HTTP probe every 30s        | Marks EC2 healthy/unhealthy                          |
| Auto Scaling Group  | aws_autoscaling_group           | Virtual Machine Scale Set   | Manages EC2 fleet size, replaces failed instances    |
| Scale-out Policy    | Target tracking CPU > 70%       | Azure Monitor CPU > 70%     | Adds 2 instances when load is high                   |
| Scale-in Policy     | Target tracking CPU < 30%       | Azure Monitor CPU < 30%     | Removes 1 instance when load is low                  |
| NAT Gateway         | aws_nat_gateway (Regional)      | Outbound via LB rules       | Private EC2s reach internet for package installs     |

---

## Learning Objectives

By completing this project you will be able to:

1. Explain how ALB, Target Groups, and ASG are connected to each other
2. Create a Launch Template with user-data to auto-configure EC2 at boot
3. Set up a Target Group with health checks and attach it to an ALB
4. Configure an ASG with min/desired/max and attach it to a Target Group
5. Add a Target Tracking Scaling Policy based on CPU utilization
6. Verify auto-healing by manually terminating an EC2 and watching ASG replace it
7. Observe load balancing by refreshing the browser and seeing different instance IDs
8. Compare ASG (AWS) with VMSS + Azure Monitor (Azure)

---

## Architecture Overview

```
                         [ Internet ]
                               |
                    [ Application Load Balancer ]
                      (public-subnet-1a, 1b)
                        /               \
          ┌──────────────────────────────────────────┐
          │  VPC: 10.0.0.0/16                        │
          │                                          │
          │  ┌── AZ-1a (private) ──┐  ┌── AZ-1b ──┐  │
          │  │  Auto Scaling Group  │  │           │  │
          │  │   [EC2] [EC2]        │  │ [EC2][EC2]│  │
          │  │   10.0.3.0/24        │  │10.0.4.0/24│  │
          │  └──────────────────────┘  └───────────┘  │
          │                                          │
          │  [Target Group: web-tg port 80]          │
          │  Scaling: CPU > 70% → scale out          │
          │           CPU < 30% → scale in           │
          └──────────────────────────────────────────┘
```

**Concepts covered:** ALB, Target Groups, Auto Scaling Groups, Launch Templates, Scaling Policies, Health Checks, Availability Zones, VMSS (Azure)

---

## AWS Console — Step-by-Step

### Step 1: Create VPC and Subnets
Use the VPC Wizard or manually:
1. VPC: `ha-app-vpc`, CIDR: `10.0.0.0/16`
2. Public Subnets: `10.0.1.0/24` (1a), `10.0.2.0/24` (1b) — for ALB
3. Private Subnets: `10.0.3.0/24` (1a), `10.0.4.0/24` (1b) — for EC2
4. Create IGW, attach to VPC
5. Create NAT Gateway in public-subnet-1a
6. Route tables: public → IGW, private → NAT

### Step 2: Create Security Groups
**ALB SG** (`alb-sg`):
- Inbound: 80, 443 from `0.0.0.0/0`

**App SG** (`app-sg`):
- Inbound: Port 80 from `alb-sg` only
- Inbound: Port 22 from your management IP
- Outbound: All

### Step 3: Create Launch Template
1. **EC2 > Launch Templates > Create Launch Template**
2. Name: `ha-app-lt`
3. AMI: Amazon Linux 2023
4. Instance type: `t3.small`
5. Security group: `app-sg`
6. Advanced details → User data:
```bash
#!/bin/bash
yum update -y
yum install -y nginx
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
echo "<h1>Hello from $INSTANCE_ID in $AZ</h1>" > /usr/share/nginx/html/index.html
systemctl start nginx
systemctl enable nginx
```

### Step 4: Create Target Group
1. **EC2 > Target Groups > Create Target Group**
2. Target type: **Instances**
3. Name: `ha-app-tg`
4. Protocol: HTTP, Port: 80
5. VPC: `ha-app-vpc`
6. Health check:
   - Protocol: HTTP
   - Path: `/`
   - Healthy threshold: 2
   - Unhealthy threshold: 3
   - Interval: 30s
   - Timeout: 5s

### Step 5: Create Application Load Balancer
1. **EC2 > Load Balancers > Create Load Balancer**
2. Type: **Application Load Balancer**
3. Name: `ha-app-alb`
4. Scheme: **Internet-facing**
5. IP type: IPv4
6. VPC: `ha-app-vpc`
7. Subnets: select **both public subnets** (1a and 1b)
8. Security group: `alb-sg`
9. Listener: HTTP:80 → Forward to `ha-app-tg`
10. Click **Create Load Balancer**

### Step 6: Create Auto Scaling Group
1. **EC2 > Auto Scaling Groups > Create Auto Scaling Group**
2. Name: `ha-app-asg`
3. Launch template: `ha-app-lt`
4. VPC: `ha-app-vpc`
5. Subnets: both **private** subnets (1a and 1b) — this spreads across AZs
6. **Attach to Load Balancer**: select `ha-app-tg`
7. Health check: EC2 + ELB health checks, grace period: 120s
8. Group size:
   - Desired: `2`
   - Minimum: `2`
   - Maximum: `6`
9. Next → **Add notifications** (optional)

### Step 7: Add Scaling Policies
In the ASG → **Automatic scaling**:

**Scale-Out Policy (CPU > 70%):**
1. Add policy → **Target tracking scaling**
2. Metric: **Average CPU utilization**
3. Target value: `70`
4. Instances need: `60` seconds before scaling
5. Scale-in cooldown: `300` seconds

**Manual test (Step Scaling alternative):**
1. Add policy → **Step scaling**
2. CloudWatch alarm: CPU > 70% for 2 periods → Add 2 instances
3. CloudWatch alarm: CPU < 30% for 5 periods → Remove 1 instance

### Step 8: Configure Availability Zone Balancing
In ASG Settings:
- **Availability Zone rebalancing**: Enabled (default)
- This ensures if 3 instances land in AZ-1a and 1 in AZ-1b after scale-out, ASG auto-rebalances

### Step 9: Test Auto Scaling
```bash
# Get ALB DNS from console
ALB_DNS="ha-app-alb-xxxxxx.us-east-1.elb.amazonaws.com"

# Test load balancing (responses come from different AZs)
for i in {1..10}; do curl http://$ALB_DNS; echo; done

# Simulate high CPU to trigger scale-out
ssh ec2-user@<instance-ip>
stress --cpu 4 --timeout 300  # install stress first: yum install stress-ng

# Watch scaling in console: EC2 > Auto Scaling Groups > Activity
```

---

## Azure Portal — Step-by-Step (VMSS)

### Step 1: Create VNet and Subnets
- VNet: `ha-app-vnet`, CIDR: `10.0.0.0/16`
- Subnets: `lb-subnet 10.0.1.0/24`, `app-subnet 10.0.2.0/24`

### Step 2: Create Azure Load Balancer
1. **Load Balancers > Create**
2. Name: `ha-app-lb`, SKU: **Standard**, Type: **Public**
3. Frontend IP: create new public IP `ha-app-lb-pip`

### Step 3: Create Virtual Machine Scale Set (VMSS)
1. **Virtual Machine Scale Sets > Create**
2. Name: `ha-app-vmss`
3. Region: same as VNet
4. Availability Zones: Zone 1, Zone 2
5. Image: Ubuntu Server 22.04
6. Size: `Standard_B2s`
7. Scaling:
   - Initial count: `2`
   - Min: `2` / Max: `6`
   - Scale-out: CPU > 70%
   - Scale-in: CPU < 30%
8. Networking:
   - VNet: `ha-app-vnet`, Subnet: `app-subnet`
   - Public IP: **None** (LB handles access)
9. Load Balancer: select `ha-app-lb`
10. Custom data (cloud-init):
```yaml
#cloud-config
packages:
  - nginx
runcmd:
  - systemctl start nginx
  - systemctl enable nginx
  - echo "<h1>Hello from $(hostname)</h1>" > /var/www/html/index.html
```

### Step 4: Configure Azure Monitor Autoscale
1. **VMSS > Scaling > Custom autoscale**
2. Default profile:
   - Min: 2, Max: 6, Default: 2
3. Add a scale-out rule:
   - Metric: **Percentage CPU**
   - Operator: Greater than, Threshold: 70
   - Duration: 5 minutes
   - Action: Increase count by 2
4. Add a scale-in rule:
   - Metric: CPU < 30 for 10 minutes
   - Action: Decrease count by 1

### Step 5: Verify in Azure
```bash
# Get LB public IP from portal
LB_IP="x.x.x.x"
for i in {1..10}; do curl http://$LB_IP; echo; done
# Different hostnames confirm load balancing works
```

---

## Testing & Verification

| Test | Expected Result |
|------|-----------------|
| `curl http://ALB_DNS` | Nginx welcome page |
| Refresh 10x | Responses from different AZs |
| Kill one instance | ALB stops routing to it (health check fails) |
| Run stress test | ASG adds instances after ~2 min |
| Stop stress test | ASG removes instances after cooldown |
| Terminate an AZ's instance | ASG auto-replaces it |

---

## Key Concepts Reinforced

| Concept          | What You Practiced                                   |
|------------------|------------------------------------------------------|
| ALB              | Internet-facing, multi-AZ, path-based routing       |
| Target Groups    | Instance-based, health checks, port mapping         |
| Launch Template  | Versioned instance config, user data, AMI           |
| Auto Scaling     | Desired/min/max, AZ balancing, cooldown periods     |
| Scaling Policies | Target tracking vs step scaling                     |
| Health Checks    | ELB + EC2 combined health, grace period             |
| VMSS (Azure)     | Scale set equivalent, zone-redundant deployment     |
