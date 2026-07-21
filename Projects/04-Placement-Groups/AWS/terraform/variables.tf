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
  default = "0.0.0.0/0"
}

variable "cluster_instance_count" {
  description = "Number of instances in Cluster PG (needs enhanced networking capable type)"
  default     = 3
}

variable "cluster_instance_type" {
  description = "Must support cluster placement (c5, r5, m5 etc — NOT t3)"
  default     = "c5.large"
}

variable "spread_instance_count" {
  description = "Max 7 per AZ for Spread PG"
  default     = 4
}

variable "partition_instance_count" {
  description = "Evenly distributed across 3 partitions"
  default     = 6
}
