variable "region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "ha-app"
}

variable "availability_zones" {
  default = ["us-east-1a", "us-east-1b"]
}

variable "ami_id" {
  description = "Amazon Linux 2023 AMI"
  default     = "ami-0c02fb55956c7d316"
}

variable "instance_type" {
  default = "t3.small"
}

variable "key_pair_name" {
  description = "EC2 Key Pair name"
}

variable "asg_min" {
  default = 2
}

variable "asg_max" {
  default = 6
}

variable "asg_desired" {
  default = 2
}
