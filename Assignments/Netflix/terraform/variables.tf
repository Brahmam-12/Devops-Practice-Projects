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

variable "acr_name" {
    type = string
    description = "Container registry name. Must be globally unique and alphanumeric only."
}

variable "create_acr" {
    type = bool
    description = "Only the dev environment creates the shared registry."
    default = false
}