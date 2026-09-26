resource "aws_security_group" "sg" {
  name = "EC2-SG"
  vpc_id = aws_vpc.vpc.id
  description = "allow-ssh"
  ingress {
    from_port = 22
    to_port = 22
    description = "SSH"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Terraform-EC2-SG"
  }
}