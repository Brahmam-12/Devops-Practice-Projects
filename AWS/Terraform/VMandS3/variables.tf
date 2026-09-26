variable "primary_region" {
  type = string
  default = "ap-south-1"
}
variable "secondary_region" {
  type = string
  default = "ap-south-2"
}
variable "bucket_name" {
  type = string
  default = "netflixs3bucket"
}
variable "instance_type" {
  type = string
  default = "t3.micro"
}
variable "primary_ami_id" {
  type = string
}
variable "secondry_ami_id" {
  type = string
}