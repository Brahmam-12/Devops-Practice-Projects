variable "rsg" {
  type        = string
  description = "Resource group name for this environment"
}

variable "location" {
  type        = string
  description = "Azure region for this environment"
}

variable "service_plan" {
  type        = string
  description = "App Service plan name"
}

variable "web_app" {
  type        = string
  description = "Web app name (globally unique)"
}