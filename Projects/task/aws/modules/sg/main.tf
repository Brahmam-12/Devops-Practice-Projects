resource "aws_security_group" "sg" {
  name = var.security_group
  ingress {
    protocol = "in"
  }
}