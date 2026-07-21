terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.region
}

# ─── VPC ────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "placement-lab-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "placement-lab-igw" }
}

resource "aws_subnet" "az1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true
  tags = { Name = "placement-lab-subnet-az1" }
}

resource "aws_subnet" "az2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = var.availability_zones[1]
  map_public_ip_on_launch = true
  tags = { Name = "placement-lab-subnet-az2" }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "placement-lab-rt" }
}

resource "aws_route_table_association" "az1" {
  subnet_id      = aws_subnet.az1.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "az2" {
  subnet_id      = aws_subnet.az2.id
  route_table_id = aws_route_table.main.id
}

resource "aws_security_group" "lab" {
  name   = "placement-lab-sg"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "placement-lab-sg" }
}

# ─── CLUSTER PLACEMENT GROUP ─────────────────────────────────────────────────
# Use case: low latency, HPC, tightly-coupled distributed computing

resource "aws_placement_group" "cluster" {
  name     = "cluster-pg"
  strategy = "cluster"
  tags     = { Name = "cluster-pg" }
}

resource "aws_instance" "cluster" {
  count                       = var.cluster_instance_count
  ami                         = var.ami_id
  instance_type               = var.cluster_instance_type
  subnet_id                   = aws_subnet.az1.id
  vpc_security_group_ids      = [aws_security_group.lab.id]
  placement_group             = aws_placement_group.cluster.id
  associate_public_ip_address = true
  key_name                    = var.key_pair_name

  tags = { Name = "cluster-node-${count.index + 1}", PlacementGroup = "cluster" }
}

# ─── SPREAD PLACEMENT GROUP ──────────────────────────────────────────────────
# Use case: critical independent instances, max hardware fault isolation

resource "aws_placement_group" "spread" {
  name         = "spread-pg"
  strategy     = "spread"
  spread_level = "rack"
  tags         = { Name = "spread-pg" }
}

resource "aws_instance" "spread" {
  count                       = var.spread_instance_count
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  subnet_id                   = count.index % 2 == 0 ? aws_subnet.az1.id : aws_subnet.az2.id
  vpc_security_group_ids      = [aws_security_group.lab.id]
  placement_group             = aws_placement_group.spread.id
  associate_public_ip_address = true
  key_name                    = var.key_pair_name

  tags = { Name = "spread-node-${count.index + 1}", PlacementGroup = "spread" }
}

# ─── PARTITION PLACEMENT GROUP ───────────────────────────────────────────────
# Use case: distributed big data systems (Hadoop, Cassandra, Kafka)

resource "aws_placement_group" "partition" {
  name            = "partition-pg"
  strategy        = "partition"
  partition_count = 3
  tags            = { Name = "partition-pg" }
}

resource "aws_instance" "partition" {
  count                       = var.partition_instance_count
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.az1.id
  vpc_security_group_ids      = [aws_security_group.lab.id]
  placement_group             = aws_placement_group.partition.id
  associate_public_ip_address = true
  key_name                    = var.key_pair_name

  placement_partition_number = (count.index % 3) + 1

  tags = {
    Name           = "partition-node-${count.index + 1}"
    PlacementGroup = "partition"
    Partition      = tostring((count.index % 3) + 1)
  }
}

# ─── OUTPUTS ────────────────────────────────────────────────────────────────

output "cluster_pg_name" {
  value = aws_placement_group.cluster.name
}

output "spread_pg_name" {
  value = aws_placement_group.spread.name
}

output "partition_pg_name" {
  value = aws_placement_group.partition.name
}

output "cluster_instance_ips" {
  value = aws_instance.cluster[*].public_ip
}

output "spread_instance_ips" {
  value = aws_instance.spread[*].public_ip
}

output "partition_instance_ips" {
  value = aws_instance.partition[*].public_ip
}
