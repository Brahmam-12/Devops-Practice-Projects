variable "vpc_id" {
  type = string
}

variable "subnets" {
  type = object({
    availability_zone = string
    public_ip = bool
    cidr_block = string
  })
}