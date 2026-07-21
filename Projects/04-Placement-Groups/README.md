# Project 4: Placement Groups & Availability Sets Lab

## Project Description

This project answers a question that Projects 1–3 never asked: **where exactly does your EC2 instance physically land in AWS?**

When you launch an EC2, AWS places it on a physical server (host) somewhere in the Availability Zone. By default you have no control over which rack, which host, or how close it is to your other EC2s. **Placement Groups** give you that control.

This is a **lab-style project** — you will create three different placement strategies, launch EC2 instances into each, and compare the results (latency, fault isolation, partition assignment).

### The Three Placement Strategies

```
CLUSTER                    SPREAD                      PARTITION
───────────────────────    ────────────────────────    ──────────────────────────────
Goal: Ultra-low latency    Goal: Max fault isolation   Goal: Group isolation for
      + max bandwidth                                         big data systems

All EC2s on the            Each EC2 goes to a          EC2s split into groups
SAME physical rack.        DIFFERENT physical rack.     (partitions). No two
                                                        partitions share hardware.
Same AZ required.          Up to 7 EC2s per AZ.        Up to 7 partitions per AZ.

┌──────────────┐           Rack1  Rack2  Rack3         Part-0  Part-1  Part-2
│ Physical Rack│           [EC2]  [EC2]  [EC2]         [EC2]   [EC2]   [EC2]
│ [EC2][EC2]  │                                        [EC2]   [EC2]   [EC2]
│ [EC2][EC2]  │           If Rack2 fails:              No shared HW between
└──────────────┘           only 1 EC2 affected.        partitions (HBase/Kafka)

Use: HPC, MPI, ML          Use: Critical primary        Use: Hadoop, Cassandra,
     training, Redis              database replicas,         Kafka, HBase
     cluster, game servers        ZooKeeper nodes
```

### How this maps to Azure

```
AWS Placement Group        Azure Equivalent               Key Difference
─────────────────────────────────────────────────────────────────────────────
Cluster PG                 Proximity Placement Group       Azure PPG = same data center
(same rack, low latency)   (same data center)              AWS Cluster = same rack (closer)

Spread PG                  Availability Set (FD=3)         Azure FD = same rack concept
(different racks)          Fault Domains                   AWS Spread = max 7/AZ

Partition PG               No direct Azure equivalent      Azure uses Availability Zones
(isolated groups)          (Avail. Zones are closer)       for large distributed systems
```

### What Fault Domains and Update Domains mean (Azure)

**Fault Domain (FD)** — a physical rack that shares power supply and network switch.
- FD 0, FD 1, FD 2 = three separate racks
- If the power to Rack 0 fails → only VMs in FD 0 are affected
- VMs in FD 1 and FD 2 keep running

**Update Domain (UD)** — a logical group for planned maintenance (patching/rebooting hosts).
- Azure never reboots two UDs at the same time
- With UD=5: Azure patches 1 group → waits → patches next group
- Your app stays up during Azure maintenance

```
Availability Set with FD=3, UD=5:

        FD 0         FD 1         FD 2
        (Rack A)     (Rack B)     (Rack C)
UD 0:   [VM-1]
UD 1:               [VM-2]
UD 2:                            [VM-3]
UD 3:   [VM-4]
UD 4:               [VM-5]

→ If Rack A (FD 0) loses power: VM-1 and VM-4 go down. VM-2, 3, 5 stay up.
→ If Azure patches UD 0: only VM-1 reboots. All others running.
```

---

## Project Details

| Item                   | Details                                              |
|------------------------|------------------------------------------------------|
| **Project Name**       | Placement Groups & Availability Sets Lab             |
| **Cloud Platforms**    | AWS + Azure (parallel implementation)                |
| **Difficulty**         | Intermediate                                         |
| **Estimated Time**     | 1.5–2 hours (console) / 20 min (Terraform/Bicep)    |
| **AWS Region**         | us-east-1                                            |
| **Azure Region**       | East US                                              |
| **AWS PGs created**    | 3 (Cluster + Spread + Partition)                     |
| **Azure resources**    | Availability Set (FD=3, UD=5) + Proximity PG         |
| **EC2 count (AWS)**    | 3 cluster + 4 spread + 6 partition = 13 instances    |
| **VM count (Azure)**   | 3 in Avail. Set + 3 in PPG + 3 zone-redundant = 9   |
| **IaC Files**          | `AWS/terraform/` and `Azure/bicep/`                  |
| **Diagrams**           | `Drawings/aws-placement.tldr` and `azure-avset.tldr` |

> **Cost note:** Cluster PG requires instance types that support enhanced networking (c5, r5, m5 family — NOT t3). These are more expensive. Terminate after testing.

---

## Requirements

### Before You Start

**AWS Prerequisites:**
- [ ] AWS account with IAM permissions (EC2, VPC)
- [ ] AWS CLI installed and configured
- [ ] Terraform v1.5+ (for IaC deployment)
- [ ] An EC2 Key Pair in us-east-1
- [ ] A VPC with public subnets already created (or use Project 1's VPC)

**Azure Prerequisites:**
- [ ] Azure account with Subscription
- [ ] Azure CLI installed (`az login`)
- [ ] Bicep CLI installed
- [ ] Resource Group: `placement-lab-rg` in East US

**Knowledge Prerequisites:**
- [ ] What EC2 instances are and how to launch them (Project 1)
- [ ] What Availability Zones are (covered in your VPC notes)
- [ ] What "high availability" means for compute

---

## What You Will Build

| Component                 | AWS Resource                    | Azure Resource                      | Purpose                                             |
|---------------------------|---------------------------------|-------------------------------------|-----------------------------------------------------|
| Cluster Placement Group   | aws_placement_group (cluster)   | Proximity Placement Group (PPG)     | Low latency — all instances on same rack/data center|
| 3 Cluster EC2s            | c5.large instances              | 3 VMs in PPG                        | Test latency between co-located instances           |
| Spread Placement Group    | aws_placement_group (spread)    | Availability Set (FD=3)             | Max HA — each instance on different physical rack   |
| 4 Spread EC2s             | t3.micro across 2 AZs           | 3 VMs across 3 Fault Domains        | Test fault isolation — 1 rack fails, others survive |
| Partition Placement Group | aws_placement_group (partition) | No direct equivalent (use AZ zones) | Grouped isolation for distributed systems           |
| 6 Partition EC2s          | t3.micro, 2 per partition       | Zone-redundant VMs (Zone 1/2/3)     | Test partition assignment — no cross-partition HW   |
| VPC + Subnets             | Simple VPC with public subnets  | VNet with lab-subnet                | Network for all lab instances                       |

---

## Learning Objectives

By completing this project you will be able to:

1. Create all three types of AWS Placement Groups and explain when to use each
2. Launch EC2 instances into a specific Placement Group and verify the assignment
3. Explain why Cluster PG needs enhanced networking instance types (not t3)
4. Measure the latency difference between Cluster and Spread instances using iperf3
5. Create an Azure Availability Set and explain Fault Domains vs Update Domains
6. Deploy VMs across Fault Domains and simulate a rack failure
7. Create a Proximity Placement Group and explain how it differs from Availability Sets
8. Map AWS placement concepts to their Azure equivalents

---

## Architecture Overview

```
AWS Placement Groups                    Azure Equivalents
─────────────────────────────────────────────────────────────

CLUSTER (Low Latency)         PROXIMITY PLACEMENT GROUP
┌──────────────────┐          ┌──────────────────────┐
│  Same Rack/Host  │          │  Same Data Center    │
│  [EC2][EC2][EC2] │◄──────► │  [VM][VM][VM]        │
│  <1ms latency    │          │  Low latency          │
└──────────────────┘          └──────────────────────┘

SPREAD (High Availability)    AVAILABILITY SET (FD=3, UD=5)
┌─────────────────────────┐   ┌───────────────────────────┐
│ Rack1  Rack2  Rack3     │   │  FD0    FD1    FD2        │
│ [EC2]  [EC2]  [EC2]     │◄─► │  [VM]   [VM]   [VM]      │
│ Max 7 per AZ            │   │  Spread across HW faults  │
└─────────────────────────┘   └───────────────────────────┘

PARTITION (Large Distributed)
┌──────────────────────────────────────┐
│  Part-0     Part-1      Part-2       │
│  [EC2][EC2] [EC2][EC2]  [EC2][EC2]   │
│  No shared hardware between parts    │
│  Good for: Hadoop, Cassandra, Kafka  │
└──────────────────────────────────────┘
```

**Concepts covered:** Placement Groups (Cluster/Spread/Partition), Availability Sets, Proximity Placement Groups, Fault Domains, Update Domains

---

## AWS Console — Step-by-Step

### Step 1: Create a Cluster Placement Group

**Use case:** HPC, tightly-coupled distributed apps, MPI workloads, low-latency requirements

1. **EC2 > Placement Groups > Create Placement Group**
2. Name: `cluster-pg`
3. Strategy: **Cluster**
4. Click **Create Group**

Launch instances:
1. **EC2 > Launch Instance**
2. Name: `cluster-node-1` (repeat for 3 nodes)
3. Instance type: **c5n.large** or `c5.xlarge` (cluster PG needs higher-end instances)
4. Advanced → Placement Group: `cluster-pg`
5. Subnet: **same AZ for all** (cluster PG must be in one AZ)
6. Launch all in the same subnet/AZ

> **Key constraint:** All instances in a Cluster PG must be in the same AZ.
> If capacity isn't available, launch all at once using a fleet request.

### Step 2: Create a Spread Placement Group

**Use case:** Critical instances that must survive hardware failures independently

1. **EC2 > Placement Groups > Create Placement Group**
2. Name: `spread-pg`
3. Strategy: **Spread**
4. Spread level: **Rack** (default) or **Host** (dedicated hardware)
5. Click **Create Group**

Launch instances:
1. Launch 6 instances (max 7 per AZ per Spread PG)
2. Name: `spread-node-1` through `spread-node-6`
3. Advanced → Placement Group: `spread-pg`
4. Can use different AZs for each instance

> **Key constraint:** Max 7 instances per AZ in a Spread PG.
> Each instance goes to a different rack — best HA.

### Step 3: Create a Partition Placement Group

**Use case:** HDFS, HBase, Cassandra, Kafka — large distributed workloads

1. **EC2 > Placement Groups > Create Placement Group**
2. Name: `partition-pg`
3. Strategy: **Partition**
4. Number of partitions: `3`
5. Click **Create Group**

Launch instances and assign to partitions:
1. Launch 6 instances (2 per partition)
2. Advanced → Placement Group: `partition-pg`
3. **Partition**: set to 1, 2, or 3 (assign 2 instances per partition)

Check partition assignment: Select instance → **Details** → Partition Number

> **Key concept:** Instances in different partitions share no underlying hardware.
> Instances within the same partition may share hardware.

### Step 4: Compare Latency (Cluster vs Spread)

```bash
# Install ping testing tool
sudo yum install -y fping

# Test latency between cluster nodes (expected: <1ms)
fping -c 10 10.0.1.x 10.0.1.y 10.0.1.z  # cluster nodes

# Test latency between spread nodes (expected: 1-5ms, different racks)
fping -c 10 10.0.2.x 10.0.2.y 10.0.2.z  # spread nodes

# iperf3 bandwidth test between cluster nodes
sudo yum install -y iperf3
# On node 1: iperf3 -s
# On node 2: iperf3 -c 10.0.1.x  # Cluster: ~25Gbps, Spread: ~10Gbps
```

### Step 5: View Placement Group Details
```bash
# Using AWS CLI
aws ec2 describe-placement-groups

# Describe instances in a PG
aws ec2 describe-instances \
  --filters "Name=placement-group-name,Values=cluster-pg" \
  --query "Reservations[].Instances[].{ID:InstanceId,AZ:Placement.AvailabilityZone,Partition:Placement.PartitionNumber}"
```

---

## Azure Portal — Step-by-Step

### Step 1: Create an Availability Set

**Availability Set** = protection against hardware failures and planned maintenance

1. **Availability Sets > Create**
2. Name: `ha-avset`
3. Resource Group: create or select
4. Region: East US
5. Fault domains: `3` (max 3 in most regions)
6. Update domains: `5` (max 20, default 5)
7. Use managed disks: **Yes**
8. Click **Create**

**What this gives you:**
- FD = physical rack isolation (power + network)
- UD = logical group for rolling maintenance (Azure only reboots 1 UD at a time)

### Step 2: Create VMs in the Availability Set
1. **Virtual Machines > Create**
2. Name: `avset-vm-1`
3. Availability options: **Availability Set**
4. Availability Set: `ha-avset`
5. Create 3 VMs total (they get assigned to FD 0, 1, 2 automatically)

Check fault domain assignment:
- **Availability Set > Virtual Machines** → each VM shows FD and UD number

### Step 3: Create a Proximity Placement Group (Cluster equivalent)

**Proximity Placement Group** = co-locate VMs for low latency

1. **Proximity Placement Groups > Create**
2. Name: `low-latency-ppg`
3. Intent type: **Standard** (or Virtual Machines)
4. Click **Create**

Create VMs in the PPG:
1. **Virtual Machines > Create**
2. Advanced tab → **Proximity placement group**: `low-latency-ppg`
3. Availability options: **No infrastructure redundancy** (or Availability Zone for zone-level)
4. Create 3 VMs

> VMs in the same PPG are placed in the same data center building for minimum latency.

### Step 4: Create VMs in Availability Zones (Best HA)

For zone-redundant deployments:
1. **Virtual Machines > Create**
2. Availability options: **Availability Zone**
3. Zone: 1 (for vm-1), Zone 2 (for vm-2), Zone 3 (for vm-3)
4. This spreads VMs across separate data centers (not just racks)

### Step 5: Simulate Fault Domain Failure
1. In Azure portal, note which VMs are in FD 0 vs FD 1 vs FD 2
2. Stop all VMs in FD 0
3. App should remain running on FDs 1 and 2
4. This simulates a rack/power failure

---

## Comparing All Strategies

| Feature              | Cluster PG    | Spread PG    | Partition PG  | Avail. Set   | PPG (Azure) |
|----------------------|---------------|--------------|---------------|--------------|-------------|
| Use case             | HPC/Low latency| Critical HA  | Big data      | General HA   | Low latency |
| Max instances        | Unlimited     | 7/AZ         | 1000s         | Unlimited    | Unlimited   |
| AZ restriction       | Single AZ     | Multi-AZ OK  | Multi-AZ OK   | Single region| Same DC     |
| Hardware isolation   | Shared rack   | Different rack| Per partition | Per FD       | Same DC     |
| Network performance  | Highest       | Standard     | Standard      | Standard     | High        |
| Azure equivalent     | PPG           | Avail. Set   | PPG + Zones   | Avail. Set   | PPG         |

---

## Testing & Verification

```bash
# Verify placement group for an instance
aws ec2 describe-instances --instance-ids i-xxxx \
  --query "Reservations[0].Instances[0].Placement"

# Expected output for cluster PG:
# {
#   "GroupName": "cluster-pg",
#   "Tenancy": "default",
#   "AvailabilityZone": "us-east-1a"
# }

# For partition PG, you'll also see:
# "PartitionNumber": 1
```

---

## Key Concepts Reinforced

| Concept            | What You Practiced                                        |
|--------------------|-----------------------------------------------------------|
| Cluster PG         | Single AZ, same rack, ultra-low latency                  |
| Spread PG          | Different racks, max HA, 7 instances/AZ limit            |
| Partition PG       | Grouped hardware isolation for distributed systems       |
| Availability Set   | Azure FD + UD, protects against rack and patch failures  |
| PPG (Azure)        | Co-location for latency, doesn't guarantee HA by itself  |
| FD vs UD           | Fault Domain = physical rack; Update Domain = patch group |
