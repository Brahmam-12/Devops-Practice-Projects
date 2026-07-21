terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.region
}

# ─── VPCs ───────────────────────────────────────────────────────────────────

resource "aws_vpc" "hub" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "hub-vpc" }
}

resource "aws_vpc" "spoke_a" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "spoke-a-vpc" }
}

resource "aws_vpc" "spoke_b" {
  cidr_block           = "10.2.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "spoke-b-vpc" }
}

# ─── SUBNETS ────────────────────────────────────────────────────────────────

resource "aws_subnet" "hub_private" {
  count             = 2
  vpc_id            = aws_vpc.hub.id
  cidr_block        = ["10.0.1.0/24", "10.0.2.0/24"][count.index]
  availability_zone = var.availability_zones[count.index]
  tags = { Name = "hub-private-subnet-${count.index + 1}" }
}

resource "aws_subnet" "hub_public" {
  vpc_id                  = aws_vpc.hub.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true
  tags = { Name = "hub-public-subnet" }
}

resource "aws_subnet" "spoke_a" {
  count             = 2
  vpc_id            = aws_vpc.spoke_a.id
  cidr_block        = ["10.1.1.0/24", "10.1.2.0/24"][count.index]
  availability_zone = var.availability_zones[count.index]
  tags = { Name = "spoke-a-subnet-${count.index + 1}" }
}

resource "aws_subnet" "spoke_b" {
  count             = 2
  vpc_id            = aws_vpc.spoke_b.id
  cidr_block        = ["10.2.1.0/24", "10.2.2.0/24"][count.index]
  availability_zone = var.availability_zones[count.index]
  tags = { Name = "spoke-b-subnet-${count.index + 1}" }
}

# ─── INTERNET GATEWAY (Hub only) ────────────────────────────────────────────

resource "aws_internet_gateway" "hub" {
  vpc_id = aws_vpc.hub.id
  tags   = { Name = "hub-igw" }
}

resource "aws_route_table" "hub_public" {
  vpc_id = aws_vpc.hub.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hub.id
  }
  tags = { Name = "hub-public-rt" }
}

resource "aws_route_table_association" "hub_public" {
  subnet_id      = aws_subnet.hub_public.id
  route_table_id = aws_route_table.hub_public.id
}

# ─── VPC PEERING ────────────────────────────────────────────────────────────

resource "aws_vpc_peering_connection" "hub_to_spoke_a" {
  vpc_id      = aws_vpc.hub.id
  peer_vpc_id = aws_vpc.spoke_a.id
  auto_accept = true
  tags = { Name = "hub-to-spoke-a" }
}

resource "aws_vpc_peering_connection" "hub_to_spoke_b" {
  vpc_id      = aws_vpc.hub.id
  peer_vpc_id = aws_vpc.spoke_b.id
  auto_accept = true
  tags = { Name = "hub-to-spoke-b" }
}

# ─── ROUTE TABLES WITH PEERING ROUTES ───────────────────────────────────────

# Hub routes → both spokes
resource "aws_route_table" "hub_private" {
  vpc_id = aws_vpc.hub.id

  route {
    cidr_block                = "10.1.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_spoke_a.id
  }
  route {
    cidr_block                = "10.2.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_spoke_b.id
  }
  tags = { Name = "hub-private-rt" }
}

resource "aws_route_table_association" "hub_private" {
  count          = length(aws_subnet.hub_private)
  subnet_id      = aws_subnet.hub_private[count.index].id
  route_table_id = aws_route_table.hub_private.id
}

# Spoke-A routes → hub only
resource "aws_route_table" "spoke_a" {
  vpc_id = aws_vpc.spoke_a.id

  route {
    cidr_block                = "10.0.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_spoke_a.id
  }
  tags = { Name = "spoke-a-rt" }
}

resource "aws_route_table_association" "spoke_a" {
  count          = length(aws_subnet.spoke_a)
  subnet_id      = aws_subnet.spoke_a[count.index].id
  route_table_id = aws_route_table.spoke_a.id
}

# Spoke-B routes → hub only
resource "aws_route_table" "spoke_b" {
  vpc_id = aws_vpc.spoke_b.id

  route {
    cidr_block                = "10.0.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.hub_to_spoke_b.id
  }
  tags = { Name = "spoke-b-rt" }
}

resource "aws_route_table_association" "spoke_b" {
  count          = length(aws_subnet.spoke_b)
  subnet_id      = aws_subnet.spoke_b[count.index].id
  route_table_id = aws_route_table.spoke_b.id
}

# ─── SECURITY GROUPS ────────────────────────────────────────────────────────

resource "aws_security_group" "hub" {
  name   = "hub-sg"
  vpc_id = aws_vpc.hub.id
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.1.0.0/16", "10.2.0.0/16"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "hub-sg" }
}

resource "aws_security_group" "spoke_a" {
  name   = "spoke-a-sg"
  vpc_id = aws_vpc.spoke_a.id
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "spoke-a-sg" }
}

resource "aws_security_group" "spoke_b" {
  name   = "spoke-b-sg"
  vpc_id = aws_vpc.spoke_b.id
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "spoke-b-sg" }
}

# ─── TEST INSTANCES ──────────────────────────────────────────────────────────

resource "aws_instance" "hub_bastion" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.hub_public.id
  vpc_security_group_ids      = [aws_security_group.hub.id]
  associate_public_ip_address = true
  key_name                    = var.key_pair_name
  tags = { Name = "hub-bastion" }
}

resource "aws_instance" "hub_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.hub_private[0].id
  vpc_security_group_ids = [aws_security_group.hub.id]
  key_name               = var.key_pair_name
  tags = { Name = "hub-vm" }
}

resource "aws_instance" "spoke_a_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.spoke_a[0].id
  vpc_security_group_ids = [aws_security_group.spoke_a.id]
  key_name               = var.key_pair_name
  tags = { Name = "spoke-a-vm" }
}

resource "aws_instance" "spoke_b_vm" {
  ami                    = var.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.spoke_b[0].id
  vpc_security_group_ids = [aws_security_group.spoke_b.id]
  key_name               = var.key_pair_name
  tags = { Name = "spoke-b-vm" }
}

# ─── OUTPUTS ────────────────────────────────────────────────────────────────

output "hub_bastion_ip" {
  value = aws_instance.hub_bastion.public_ip
}

output "hub_vm_private_ip" {
  value = aws_instance.hub_vm.private_ip
}

output "spoke_a_vm_private_ip" {
  value = aws_instance.spoke_a_vm.private_ip
}

output "spoke_b_vm_private_ip" {
  value = aws_instance.spoke_b_vm.private_ip
}

output "peering_hub_spoke_a_id" {
  value = aws_vpc_peering_connection.hub_to_spoke_a.id
}

output "peering_hub_spoke_b_id" {
  value = aws_vpc_peering_connection.hub_to_spoke_b.id
}
