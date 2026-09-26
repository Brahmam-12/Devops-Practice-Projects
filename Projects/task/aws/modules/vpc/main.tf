resource "aws_vpc" "vpc" {
  region = var.region
  cidr_block = var.cidr
  tags =  {
    name = "Terraform vpc"
  }
  lifecycle {
    prevent_destroy = false
  }
}