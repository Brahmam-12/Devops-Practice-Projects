output "resource_group_name" {
  value = module.resource.name
}

output "web_app_url" {
  value = "https://${module.webapp.default_hostname}"
}
