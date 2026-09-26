terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  # Remote state stored in S3 (created by s3-backend/main.tf first)
  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "vpc/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "company-terraform-state-locks"
  }
}

provider "aws" { region = var.region }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr

  azs             = ["${var.region}a", "${var.region}b"]
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway = true
  single_nat_gateway = true    # one NAT GW for cost savings (use false for production HA)

  # Tags required for EKS to discover subnets
  public_subnet_tags  = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }

  tags = { Project = var.project, ManagedBy = "terraform" }
}

variable "region"          { default = "us-east-1" }
variable "project"         { default = "microservices" }
variable "vpc_cidr"        { default = "10.0.0.0/16" }
variable "private_subnets" { default = ["10.0.1.0/24", "10.0.2.0/24"] }
variable "public_subnets"  { default = ["10.0.10.0/24", "10.0.11.0/24"] }

output "vpc_id"             { value = module.vpc.vpc_id }
output "private_subnet_ids" { value = module.vpc.private_subnets }
output "public_subnet_ids"  { value = module.vpc.public_subnets }
