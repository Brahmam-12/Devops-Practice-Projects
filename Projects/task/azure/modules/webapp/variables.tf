variable "service_plan" {
  type        = string
  description = "Name of the App Service plan"
}

variable "web_app" {
  type        = string
  description = "Name of the web app (must be globally unique)"
}

# Passed in from the root module - this module never creates or names the RG itself.
variable "resource_group_name" {
  type        = string
  description = "Resource group the app service plan and web app go into"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "sku_name" {
  type        = string
  description = "App Service plan SKU"
  default     = "B1"
}
