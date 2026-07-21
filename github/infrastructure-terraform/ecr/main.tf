terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  # Terraform stores state in S3 — same bucket, different key per module
  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "ecr/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "company-terraform-state-locks"
  }
}

provider "aws" { region = var.region }

# ─── ECR REPOSITORY: user-service ────────────────────────────────────────────
# ECR = Elastic Container Registry — AWS's private Docker image registry.
# Jenkins builds the Docker image → pushes it here → EKS pulls it from here.
#
# WHY NOT DOCKER HUB?
#   ECR is private (no accidental public exposure), inside AWS network (fast pulls),
#   and free for images pulled from within the same AWS region.
resource "aws_ecr_repository" "user_service" {
  name                 = "user-service"
  image_tag_mutability = "MUTABLE"    # allows reusing tags like "latest" or "stable"
                                       # IMMUTABLE = once pushed, tag cannot be overwritten

  image_scanning_configuration {
    scan_on_push = true                # automatically scans every image for CVEs on push
                                       # scan results appear in ECR console — no extra cost
  }

  tags = {
    Service   = "user-service"
    ManagedBy = "terraform"
  }
}

# Lifecycle policy: auto-delete old images to prevent storage cost from accumulating.
# Without this, ECR keeps EVERY image ever pushed (Jenkins builds daily = hundreds of images).
# Rule: keep the 10 most recent images, delete anything older.
resource "aws_ecr_lifecycle_policy" "user_service" {
  repository = aws_ecr_repository.user_service.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images — delete older ones to save storage cost"
        selection = {
          tagStatus   = "any"             # applies to tagged AND untagged images
          countType   = "imageCountMoreThan"
          countNumber = 10                # keep 10 → if 11th pushed, oldest is deleted
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ─── ECR REPOSITORY: product-service ─────────────────────────────────────────
# Identical config to user-service — each service gets its own isolated repository.
# WHY SEPARATE REPOS PER SERVICE?
#   - Independent lifecycle policies (could keep 20 for one, 5 for another)
#   - Independent IAM permissions (service A cannot push to service B's repo)
#   - Clean audit trail — each repo shows only its own build history
resource "aws_ecr_repository" "product_service" {
  name                 = "product-service"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Service   = "product-service"
    ManagedBy = "terraform"
  }
}

resource "aws_ecr_lifecycle_policy" "product_service" {
  repository = aws_ecr_repository.product_service.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images — delete older ones to save storage cost"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ─── VARIABLES & OUTPUTS ──────────────────────────────────────────────────────
variable "region" { default = "us-east-1" }

# Outputs = values Jenkins needs to push images.
# Jenkins reads these via: aws ecr get-login-password | docker login <url>
output "user_service_ecr_url" {
  description = "Full ECR URL for user-service — paste this into Jenkinsfile IMAGE variable"
  value       = aws_ecr_repository.user_service.repository_url
  # Example: 123456789.dkr.ecr.us-east-1.amazonaws.com/user-service
}

output "product_service_ecr_url" {
  description = "Full ECR URL for product-service — paste this into Jenkinsfile IMAGE variable"
  value       = aws_ecr_repository.product_service.repository_url
}
