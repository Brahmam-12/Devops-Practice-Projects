resource "aws_subnet" "subnet" {
  for_each = var.subnets
  vpc_id = var.vpc_id
  cidr_block = each.value.cidr_block
  assign_ipv6_address_on_creation = each.value.public_ip
  availability_zone = each.value.availability_zone
}