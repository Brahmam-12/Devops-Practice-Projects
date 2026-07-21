variable "region" {
  default = "us-east-1"
}

variable "availability_zones" {
  default = ["us-east-1a", "us-east-1b"]
}

variable "ami_id" {
  default = "ami-0c02fb55956c7d316"
}

variable "key_pair_name" {
  description = "EC2 Key Pair name"
}

variable "allowed_ssh_cidr" {
  description = "Your IP CIDR for SSH"
  default     = "0.0.0.0/0"
}
