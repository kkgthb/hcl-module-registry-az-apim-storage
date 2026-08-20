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

resource "azurerm_storage_container" "enterprise_hcl_mod_reg_storacct_container" {
  name                  = "enterprise-hcl-mod-reg-container"
  storage_account_id    = var.storacct_instance.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "enterprise_hcl_mod_reg_storacct_container_blob_data_contributor_roleassignment" {
  principal_id         = data.azurerm_client_config.current_azurerm_config.object_id # Realistically, a Security Group of module authors, but I'll do for now.
  role_definition_name = "Storage Blob Data Contributor"
  scope                = azurerm_storage_container.enterprise_hcl_mod_reg_storacct_container.id
}
