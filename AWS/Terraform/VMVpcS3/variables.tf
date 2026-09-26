variable "aws_region" {
  type = string
}
variable "vpc_cidr" {
  description = "vpc cidr block"
  type = string
}
variable "subnet_cidr" {
    description = "subnet cidr"
  type = list(string)
}
variable "subnet_names" {
  description = "subnet names"
  type = list(string)
}
variable "instance_count" {
  type = number
}
variable "instance_type" {
  type = string
  description = "instance type"
}
variable "ami_id" {
  description = "ami id"
  type = string
}
variable "bucket_count" {
  description = "number of s3 buckets"
  type = number
}
variable "bucket_prefix" {
  type = string
  description = "bucket prefix"
}