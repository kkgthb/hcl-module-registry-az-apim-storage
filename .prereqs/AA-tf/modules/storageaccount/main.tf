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

resource "random_string" "my_storageaccount_generated_name" {
  length  = 8
  lower   = true
  numeric = false
  special = false
  upper   = false
}

resource "azurerm_storage_account" "my_storacct" {
  # Authorship credit:  one of my peers.  I just added commentary and renamed things.
  name                             = "storacct${random_string.my_storageaccount_generated_name.result}"
  location                         = var.resource_group.location
  resource_group_name              = var.resource_group.name
  account_kind                     = "StorageV2"
  account_tier                     = "Standard" # Cheap is fine
  account_replication_type         = "LRS"      # Cheap is fine
  access_tier                      = "Hot"      # But it does need to return reasonably promptly, so not "Cool"
  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  local_user_enabled               = false
  sftp_enabled                     = false
}
