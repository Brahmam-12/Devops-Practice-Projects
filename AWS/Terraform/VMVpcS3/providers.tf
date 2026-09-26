terraform {
  required_version = ">=1.4"
  required_providers {
    aws = {
        version = ">=5.0"
        source = "hashicorp/aws"
    }
  }
}

provider "aws" {
  region = var.aws_region
}