# ── S3 Backend for Terraform State ───────────────────────────────────────────
# Create this FIRST before any other Terraform code.
# Once created, all other modules store their state here.
# Run manually ONCE: terraform init && terraform apply

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.region
}

# S3 bucket stores the terraform.tfstate files for all modules
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.bucket_name    # must be globally unique
  tags   = { Name = "terraform-state", ManagedBy = "terraform" }
}

# Versioning keeps history of every state file — allows rollback
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration { status = "Enabled" }
}

# DynamoDB table for state locking
# Prevents two engineers from running terraform apply at the same time
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.bucket_name}-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

variable "region"      { default = "us-east-1" }
variable "bucket_name" { default = "company-terraform-state" }

output "bucket_name"        { value = aws_s3_bucket.terraform_state.bucket }
output "dynamodb_table_name" { value = aws_dynamodb_table.terraform_locks.name }
