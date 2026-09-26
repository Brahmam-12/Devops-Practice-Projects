variable "resource_group_name" {
    type = string
    description = "Resource Group"
}

variable "location" {
    type = string
    description = "Location"
}

variable "webapp_name" {
    type = string
}

variable app_service_plan{
    type = string
}