resource "aws_vpc" "vpc" {
  region = var.aws_region
  cidr_block = var.vpc_cidr
  tags = {
    "Name" = "Terraform VPC"
  }
  lifecycle { //when you run terraform destory vpc wont delete
    prevent_destroy = false
  }
}
