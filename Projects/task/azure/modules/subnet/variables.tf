variable "rsg" {
  type = string
}
variable "subnets" {
  type = object({
    name = string
    address_prefix = list(string)
    public_ip = bool
  })
}
variable "vnet_name" {
    type = string 
}