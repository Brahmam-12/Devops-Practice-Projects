variable "app_name" {
    description = "App registartion name"
    type = string
}
variable "password_expiry" {
  description = "Service principal password expiry"
  type = string
}
variable "subscription_id" {
  description = "Subscription id"
  type = string
}
variable "tenant_id" {
  description = "Tenant id"
  type = string
}
variable "project_name" {
  description = "Project Name"
  type = string
}
variable "org_url" {
  description = "Org url"
  type = string
}
variable "token" {
  description = "Token"
  sensitive = true
  type = string
}
variable "subscription_name" {
  description = "Subscription name"
  type = string
}
variable "service_name" {
  description = "Service connection name"
  type = string
}