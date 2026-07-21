terraform {
  required_providers {
    aws        = { source = "hashicorp/aws",        version = "~> 5.0" }
    kubernetes = { source = "hashicorp/kubernetes",  version = "~> 2.0" }
  }
  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "eks/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "company-terraform-state-locks"
  }
}

provider "aws" { region = var.region }

# Read VPC outputs from the vpc module's remote state
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "company-terraform-state"
    key    = "vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = "1.30"

  vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids

  cluster_endpoint_public_access = true   # enables kubectl from your laptop

  eks_managed_node_groups = {
    default = {
      # ── THE THREE NUMBERS ───────────────────────────────────────────────────
      # desired_size = how many nodes to start with when cluster is created
      #                Cluster Autoscaler changes this number at runtime (up/down)
      #                Do NOT change desired_size in Terraform after cluster exists —
      #                Terraform would fight with Cluster Autoscaler over this value
      #
      # min_size     = floor — Cluster Autoscaler will NEVER go below this
      #                even if all pods are removed, 1 node stays running
      #
      # max_size     = ceiling — Cluster Autoscaler will NEVER exceed this
      #                protects against runaway scaling and unexpected AWS bill
      #                increase this in Terraform when your app grows beyond 5 nodes
      min_size       = 1
      max_size       = 5
      desired_size   = 2

      instance_types = ["t3.medium"]   # 2 vCPU, 4GB RAM per node

      # ── CLUSTER AUTOSCALER DISCOVERY TAGS ───────────────────────────────────
      # Cluster Autoscaler runs as a pod inside the cluster.
      # It finds which ASG (Auto Scaling Group) to scale by looking for these tags.
      # Without these tags → Cluster Autoscaler cannot find the node group → no scaling.
      # The cluster name in the second tag MUST match var.cluster_name below.
      tags = {
        "k8s.io/cluster-autoscaler/enabled"                   = "true"
        "k8s.io/cluster-autoscaler/microservices-eks"         = "owned"
      }
    }
  }

  tags = { Project = var.project, ManagedBy = "terraform" }
}

variable "region"       { default = "us-east-1" }
variable "project"      { default = "microservices" }
variable "cluster_name" { default = "microservices-eks" }

output "cluster_name"     { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
