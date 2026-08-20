data "azurerm_client_config" "current_azurerm_config" {
  lifecycle {
    postcondition {
      condition     = (coalesce(self.client_id, "") == "04b07795-8ddb-461a-bbee-02f9e1bf7b46")
      error_message = "AzureRM login state client ID, in submodule, is not the well-known Azure CLI GUID."
    }
    postcondition {
      condition     = (coalesce(self.object_id, "") != "")
      error_message = "AzureRM login state, in submodule, does not bear a logged-in user object ID."
    }
  }
}

resource "random_string" "my_apim_generated_name" {
  length  = 13
  lower   = true
  numeric = false
  special = false
  upper   = false
}

resource "azurerm_api_management" "my_apim" {
  name                = "apim${random_string.my_apim_generated_name.result}"
  location            = var.resource_group.location
  resource_group_name = var.resource_group.name
  publisher_name      = "Demo Publisher"
  publisher_email     = "admin@example.com"
  sku_name            = "Consumption_0"
  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "container_module_registry_blob_contributor" {
  principal_id         = azurerm_api_management.my_apim.identity[0].principal_id
  role_definition_name = "Storage Blob Data Reader"
  scope                = var.storacct_instance.id
}
