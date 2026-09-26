terraform {
    required_version = ">=1.4"
    required_providers {
      azurerm = {
        source = "hashicorp/azurerm"
        version = ">=4.0"
      }
      azuredevops={
        source = "microsoft/azuredevops"
        version = ">=1.0"
      }
      azuread = {
        source = "hashicorp/azuread"
        version = ">=2.0"
      }
    }
}
data "azuredevops_project" "repo" {
  name = var.project_name
}


provider "azuread" {
  tenant_id = var.tenant_id
}
provider "azuredevops" {
  org_service_url = var.project_url
  personal_access_token = var.url_token
}
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}


resource "azurerm_resource_group" "rsg"{
  name =var.resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "sa"{
  name = var.storage_account_name
  location = var.location
  resource_group_name = azurerm_resource_group.rsg.name
  account_tier = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "container" {
 name = var.container_name
 storage_account_id = azurerm_storage_account.sa.id
 container_access_type = "private"
}

resource "azuread_application" "app_registartion" {
  display_name = var.app_registration_name
}

resource "azuread_service_principal" "service_principal"{
  client_id = azuread_application.app_registartion.client_id
}

resource "azuread_application_password" "app_pass"{
  application_id = azuread_application.app_registartion.id
}

resource "azurerm_role_assignment" "role_assignement" {
  role_definition_name = "Contributor"
  principal_id = azuread_service_principal.service_principal.object_id
  scope = "/subscriptions/${var.subscription_id}"
}

resource "azuredevops_serviceendpoint_azurerm" "service_endpoint" {
  azurerm_spn_tenantid = var.tenant_id
  azurerm_subscription_id = var.subscription_id
  azurerm_subscription_name = var.subscription_name

  credentials {
    serviceprincipalid = azuread_service_principal.service_principal.client_id
    serviceprincipalkey = azuread_application_password.app_pass.value
  }
  project_id = data.azuredevops_project.repo.id
  service_endpoint_name = var.service_connection_name
}