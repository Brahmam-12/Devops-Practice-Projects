terraform {
  required_version = ">=1.4"
  required_providers {
    azurerm = {
        version = ">4.0"
        source = "hashicorp/azurerm"
    }
  }
  backend "azurerm" {
    
  }
}

provider "azurerm" {
  features {}
}
