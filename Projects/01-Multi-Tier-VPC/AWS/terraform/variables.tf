variable "region" {
  default = "us-east-1"
}

variable "project_name" {
  default = "multi-tier"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "availability_zones" {
  default = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "app_subnet_cidrs" {
  default = ["10.0.3.0/24", "10.0.4.0/24"]
}

variable "db_subnet_cidrs" {
  default = ["10.0.5.0/24", "10.0.6.0/24"]
}

variable "allowed_ssh_cidr" {
  description = "Your IP CIDR for SSH access to bastion"
  default     = "0.0.0.0/0"
}

variable "key_pair_name" {
  description = "EC2 key pair name"
}

variable "bastion_ami" {
  description = "Amazon Linux 2023 AMI (update per region)"
  default     = "ami-0c02fb55956c7d316"
}

variable "app_ami" {
  default = "ami-0c02fb55956c7d316"
}
