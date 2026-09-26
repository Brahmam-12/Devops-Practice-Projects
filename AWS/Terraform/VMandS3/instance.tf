resource "aws_instance" "primary" {
    ami = var.primary_ami_id
    region = var.primary_region
    instance_type = var.instance_type
    tags = {
      "Name" = "Brahmam"
      "Env" = "Dev"
    }
}

resource "aws_instance" "secondary"{
    provider = aws.secondary
    ami = var.secondry_ami_id
    region = var.secondary_region
    instance_type = var.instance_type
    tags = {
      "Name" = "Brahmam"
      "Env" = "Dev"
    }
}