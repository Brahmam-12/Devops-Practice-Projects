terraform {
    required_version = ">=1.1"
    required_providers {
        azurerm = {
            version = ">=4.0"
            source = "hashicorp/azurerm"
        }
    }
}
provider "azurerm" {
  features {
    
  }
}

resource "azurerm_resource_group" "rsg" {
  name = var.rsg
  location = var.location
}

resource "azurerm_storage_account" "sa" {
    name = var.storageAccount
    location = var.location
    resource_group_name = azurerm_resource_group.rsg.name
    account_tier = "Standard"
    account_replication_type = "LRS"
}

resource "azurerm_storage_container" "container" {
    name = var.container
    storage_account_id = azurerm_storage_account.sa.id
}