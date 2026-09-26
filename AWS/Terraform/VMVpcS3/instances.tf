resource "aws_instance" "ec2" {
  count = var.instance_count
  instance_type = var.instance_type
  ami = var.ami_id
  subnet_id = aws_subnet.subnet[count.index].id
  vpc_security_group_ids = [aws_security_group.sg.id]
  tags = {
    Name = "Terraform-VM-${count.index + 1}"
  }
  lifecycle {
    create_before_destroy = false // it will create a new vm if it terrafform destroy.
  }
}