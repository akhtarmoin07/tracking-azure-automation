terraform {
  # Existing state storage. Coordinates are nonsecret; authentication comes from the runner.
  # The workload creates a separate resource group and FSLogix storage account.
  backend "azurerm" {
    resource_group_name  = "RG-AVD-LAB"
    storage_account_name = "statetfmoin"
    container_name       = "tfstate"
    key                  = "sportfive/lab.tfstate"
    use_azuread_auth     = true
  }
}
